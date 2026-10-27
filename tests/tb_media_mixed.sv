`timescale 1ns/1ps
// Integrated fragmented FAT32 -> real native-size BMP -> scaler -> reference.
// The four sources include the maximum 2.36MiB/4609-cluster BMP and portrait bars.
module tb_media_mixed;
 reg clk=0,rst=1,start=0;always #4 clk=~clk;
 wire req;wire [31:0] lba;reg ready=1,bvalid=0,sd_done=0,sd_failed=0;reg [8:0] bindex=0;reg [7:0] bdata=0;
 wire begin_file;wire [31:0] file_size;wire [1:0] slot;wire fvalid,flast,fready;wire [7:0] fbyte;
 wire pvalid,plast,pdone,perror;wire [23:0] prgb;wire [20:0] paddr;wire [7:0] berror;wire [31:0] checksum;
 wire [10:0] source_width,scaled_width;wire [9:0] source_height,scaled_height;
 wire [2:0] count;wire complete;wire [7:0] error_code,state;wire [15:0] skipped;
 reg [15:0] random_bits=16'hace1;wire pready=random_bits[0]||random_bits[1];reg written=0;
 wire result_valid=perror||(pdone&&written&&!pvalid);wire result_ok=!perror;
 fat32_media dut(clk,rst,start,req,lba,ready,bvalid,bindex,bdata,sd_done,sd_failed,
  begin_file,file_size,slot,fvalid,fbyte,flast,fready,result_valid,result_ok,count,complete,error_code,skipped,state);
 bmp_stream decoder(clk,rst,begin_file,file_size,fvalid,fbyte,flast,fready,
  pvalid,prgb,paddr,plast,pready,pdone,perror,berror,checksum,source_width,source_height,scaled_width,scaled_height);
 reg [23:0] gold0[0:307199],gold1[0:307199],gold2[0:307199],gold3[0:307199];
 reg seen[0:307199];
 reg [7:0] sector[0:511];integer fd,rc,idx=-1,pixels=0,total_pixels=0,k;
 reg [31:0] actual_sum=0;string fixture;
 function [31:0] reference_sum;input integer which;integer n;reg [31:0] value;begin
  value=0;for(n=0;n<307200;n=n+1)case(which)
   0:value=value+gold0[n];1:value=value+gold1[n];2:value=value+gold2[n];3:value=value+gold3[n];
  endcase
  reference_sum=value;
 end endfunction
 reg [31:0] sums[0:3];
 initial begin
  fixture="assets/mixed_fat32.img";rc=$value$plusargs("IMAGE=%s",fixture);
  fd=$fopen(fixture,"rb");if(!fd)$fatal(1,"cannot open mixed fixture");
  $readmemh("assets/reference_extended/01_DAY.hex",gold0);$readmemh("assets/reference_extended/02_NIGHT.hex",gold1);
  $readmemh("assets/reference_extended/03_WARN.hex",gold2);$readmemh("assets/reference_extended/04_PARK.hex",gold3);
  for(k=0;k<4;k=k+1)sums[k]=reference_sum(k);
  repeat(8)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 end
 always @(posedge clk) begin
  bvalid<=0;sd_done<=0;
  if(req)begin if(idx!=-1)$fatal(1,"overlapping sector request");
   rc=$fseek(fd,lba*512,0);rc=$fread(sector,fd);if(rc!=512)$fatal(1,"sector outside disk lba=%d",lba);idx=0;ready<=0;
  end else if(idx>=0)begin
   bvalid<=1;bindex<=idx;bdata<=sector[idx];
   if(idx==511)begin idx=-1;sd_done<=1;ready<=1;end else idx=idx+1;
  end
  random_bits<={random_bits[14:0],random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
  if(begin_file)begin pixels<=0;actual_sum<=0;written<=0;for(k=0;k<307200;k=k+1)seen[k]=0;end
  if(pvalid&&pready)begin
   if(paddr>=307200||seen[paddr])$fatal(1,"pixel address outside/duplicate frame %d",paddr);
   seen[paddr]=1;
   case(slot)
    0:if(prgb!==gold0[paddr])$fatal(1,"slot0 pixel mismatch addr=%d actual=%h expected=%h",paddr,prgb,gold0[paddr]);
    1:if(prgb!==gold1[paddr])$fatal(1,"slot1 pixel mismatch addr=%d actual=%h expected=%h",paddr,prgb,gold1[paddr]);
    2:if(prgb!==gold2[paddr])$fatal(1,"slot2 pixel mismatch addr=%d actual=%h expected=%h",paddr,prgb,gold2[paddr]);
    3:if(prgb!==gold3[paddr])$fatal(1,"slot3 pixel mismatch addr=%d actual=%h expected=%h",paddr,prgb,gold3[paddr]);
   endcase
   pixels<=pixels+1;total_pixels<=total_pixels+1;actual_sum<=actual_sum+prgb;
   if(plast)begin if(pixels!=307199)$fatal(1,"wrong pixel count %d",pixels);written<=1;end
  end
  // file_slot changes on file_begin one cycle before the decoder clears its
  // sticky completion. Completion belongs to the preceding slot on that edge.
  if(result_valid&&result_ok&&!begin_file)begin
   if(checksum!==actual_sum||checksum!==sums[slot])$fatal(1,"slot %d checksum mismatch actual=%h BMP=%h gold=%h",slot,actual_sum,checksum,sums[slot]);
   if(scaled_height!=480||scaled_width!=(slot==3?360:640))$fatal(1,"scaled dimensions mismatch slot=%d %dx%d",slot,scaled_width,scaled_height);
   case(slot)
    0:if(source_width!=320||source_height!=240)$fatal(1,"slot0 source dimensions");
    1:if(source_width!=800||source_height!=600)$fatal(1,"slot1 source dimensions");
    2:if(source_width!=1024||source_height!=768)$fatal(1,"slot2 source dimensions");
    3:if(source_width!=480||source_height!=640)$fatal(1,"slot3 source dimensions");
   endcase
  end
  if(complete)begin
   if(count!=4)$fatal(1,"count=%d error=%h state=%d",count,error_code,state);
   if(total_pixels!=1228800)$fatal(1,"total pixels=%d",total_pixels);
   if(skipped!=1)$fatal(1,"invalid BMP must be skipped, skipped=%d",skipped);
   $display("TEST PASS media_mixed: 4 native mixed-size fragmented BMPs, MBR/root chain, 4609-cluster maximum BMP, portrait bars, dimension metadata/checksums, randomized stalls, 1228800 reference pixels; skipped=%d",skipped);
   $fclose(fd);$finish;
  end
 end
 initial begin #4000000000;$fatal(1,"mixed media timeout state=%d lba=%d pixels=%d count=%d",state,lba,total_pixels,count);end
endmodule
