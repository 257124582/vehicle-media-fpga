`timescale 1ns/1ps
module tb_media;
 reg clk=0,rst=1,start=0;always #4 clk=~clk;
 wire req;wire [31:0] lba;reg ready=1,bvalid=0,sd_done=0,sd_failed=0;reg [8:0] bindex=0;reg [7:0] bdata=0;
 wire begin_file;wire [31:0] file_size;wire [1:0] slot;wire fvalid,flast,fready;wire [7:0] fbyte;
 wire pvalid,plast,pdone,perror;wire [23:0] prgb;wire [20:0] paddr;wire [7:0] berror;wire [31:0] checksum;
 wire [2:0] count;wire complete;wire [7:0] error_code,state;wire [15:0] skipped;
 reg [15:0] random_bits=16'hace1;wire pready=random_bits[0]||random_bits[1];reg written=0;
 wire result_valid=perror||(pdone&&written&&!pvalid);wire result_ok=!perror;
 fat32_media dut(clk,rst,start,req,lba,ready,bvalid,bindex,bdata,sd_done,sd_failed,
  begin_file,file_size,slot,fvalid,fbyte,flast,fready,result_valid,result_ok,count,complete,error_code,skipped,state);
 bmp_stream decoder(clk,rst,begin_file,file_size,fvalid,fbyte,flast,fready,
  pvalid,prgb,paddr,plast,pready,pdone,perror,berror,checksum,,,,);
 reg [23:0] gold0[0:307199],gold1[0:307199],gold2[0:307199],gold3[0:307199];
 reg [7:0] sector[0:511];integer fd,rc,idx=-1,pixels=0,total_pixels=0;
 reg [31:0] actual_sum=0;string fixture;integer expected_count=4;
 initial begin
  fixture="assets/fat32.img";rc=$value$plusargs("IMAGE=%s",fixture);rc=$value$plusargs("COUNT=%d",expected_count);
  fd=$fopen(fixture,"rb");if(!fd)$fatal(1,"cannot open fixture");
  $readmemh("assets/reference/01_DAY.hex",gold0);$readmemh("assets/reference/02_NIGHT.hex",gold1);
  $readmemh("assets/reference/03_WARN.hex",gold2);$readmemh("assets/reference/04_PARK.hex",gold3);
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
  if(begin_file)begin pixels<=0;actual_sum<=0;written<=0;end
  if(pvalid&&pready)begin
   if(paddr>=307200)$fatal(1,"pixel address outside frame");
   case(slot)
    0:if(prgb!==gold0[paddr])$fatal(1,"slot0 pixel mismatch addr=%d actual=%h expected=%h",paddr,prgb,gold0[paddr]);
    1:if(prgb!==gold1[paddr])$fatal(1,"slot1 pixel mismatch addr=%d",paddr);
    2:if(prgb!==gold2[paddr])$fatal(1,"slot2 pixel mismatch addr=%d",paddr);
    3:if(prgb!==gold3[paddr])$fatal(1,"slot3 pixel mismatch addr=%d",paddr);
   endcase
   pixels<=pixels+1;total_pixels<=total_pixels+1;actual_sum<=actual_sum+prgb;
   if(plast)begin if(pixels!=307199)$fatal(1,"wrong pixel count %d",pixels);written<=1;end
  end
  if(complete)begin
   if(count!=expected_count)$fatal(1,"count=%d error=%h state=%d",count,error_code,state);
   if(total_pixels!=expected_count*307200)$fatal(1,"total pixels=%d",total_pixels);
   if(skipped!=1)$fatal(1,"invalid BMP must be skipped, skipped=%d",skipped);
   $display("TEST PASS media: 4 fragmented BMPs, MBR/root chain, top/down, extra offset, stalls, 1228800 pixels; skipped=%d",skipped);
   $fclose(fd);$finish;
  end
 end
 initial begin #1000000000;$fatal(1,"media timeout state=%d lba=%d pixels=%d count=%d",state,lba,total_pixels,count);end
endmodule
