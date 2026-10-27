`timescale 1ns/1ps
// Independent fixed-point reference model; native, enlargement, reduction,
// odd stride, portrait, maximum bounds, orientation, stalls and malformed files.
module tb_scaler #(parameter OW=8,OH=6);
 reg clk=0,rst=1,begin_file=0,in_valid=0,in_last=0,pready=0;
 reg [31:0] file_size=0;reg [7:0] in_byte=0;
 always #5 clk=~clk;
 wire in_ready,pvalid,plast,done,error;
 wire [23:0] rgb;wire [20:0] addr;wire [7:0] code;wire [31:0] checksum;
 wire [10:0] sw,fw;wire [9:0] sh,fh;
 bmp_stream #(.WIDTH(OW),.HEIGHT(OH)) dut(clk,rst,begin_file,file_size,in_valid,in_byte,in_last,in_ready,
  pvalid,rgb,addr,plast,pready,done,error,code,checksum,sw,sh,fw,fh);
 reg [7:0] bytes[0:2400000];reg [23:0] gold[0:OW*OH-1];reg seen[0:OW*OH-1];
 reg [15:0] lfsr=16'hbabe;reg check_pixels=0;
 reg stalled=0;reg [23:0] held_rgb;reg [20:0] held_addr;reg held_last;
 integer pixels=0,tests=0;reg [31:0] expected_sum=0;
 always @(negedge clk)begin
  lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};pready=lfsr[0]||lfsr[2];
 end
 always @(posedge clk)begin
  if(!rst&&!begin_file)begin
   if(stalled&&(!pvalid||rgb!==held_rgb||addr!==held_addr||plast!==held_last))$fatal(1,"output changed under stall");
   stalled=pvalid&&!pready;held_rgb=rgb;held_addr=addr;held_last=plast;
   if(pvalid&&pready&&check_pixels)begin
    if(addr>=OW*OH||seen[addr])$fatal(1,"invalid/duplicate address %d",addr);
    if(rgb!==gold[addr])$fatal(1,"pixel mismatch case=%0d addr=%0d rgb=%h expected=%h sy=%d sx=%d",tests,addr,rgb,gold[addr],dut.sy,dut.sx);
    seen[addr]=1;pixels=pixels+1;
    if(plast&&pixels!=OW*OH)$fatal(1,"last at %0d pixels",pixels);
   end
  end else stalled=0;
 end
 function integer red;input integer x,y;begin red=(x*17+y*29)&255;end endfunction
 function integer green;input integer x,y;begin green=(x*41+y*3)&255;end endfunction
 function integer blue;input integer x,y;begin blue=(x*7+y*61)&255;end endfunction
 function integer lerp;input integer a,b,f;begin lerp=(a*(256-f)+b*f+128)/256;end endfunction
 function integer source_channel;input integer x,y,ch;begin
  case(ch)0:source_channel=blue(x,y);1:source_channel=green(x,y);default:source_channel=red(x,y);endcase
 end endfunction
 task put32;input integer at;input [31:0] value;integer k;begin for(k=0;k<4;k=k+1)bytes[at+k]=value>>(k*8);end endtask
 task prepare;input integer w,h,td,extra,trailer;
  integer stride,size,row,x,index,py,fitw,fith,padx,pady;
  integer oy,ox,fileoy,dy,dx,stepx,stepy,cx,cy,sx,sy,sx1,sy1,fx,fy,y0,y1,a,b,ch;
  reg [23:0] result;
  begin
   stride=(w*3+3)/4*4;size=54+extra+stride*h+trailer;
   for(index=0;index<size;index=index+1)bytes[index]=0;
   bytes[0]=8'h42;bytes[1]=8'h4d;put32(2,size);put32(10,54+extra);put32(14,40);
   put32(18,w);put32(22,td?-h:h);bytes[26]=1;bytes[28]=24;put32(34,stride*h);
   for(row=0;row<h;row=row+1)begin
    py=td?row:h-1-row;
    for(x=0;x<w;x=x+1)begin
     index=54+extra+row*stride+x*3;
     bytes[index]=blue(x,py);bytes[index+1]=green(x,py);bytes[index+2]=red(x,py);
    end
    for(x=w*3;x<stride;x=x+1)bytes[54+extra+row*stride+x]=8'hde;
   end
   file_size=size;
   if(w*OH>=h*OW)begin fitw=OW;fith=h*OW/w;if(fith<1)fith=1;end
   else begin fith=OH;fitw=w*OH/h;if(fitw<1)fitw=1;end
   padx=(OW-fitw)/2;pady=(OH-fith+(td?0:1))/2;
   stepx=fitw>1?((w-1)*4096)/(fitw-1):0;stepy=fith>1?((h-1)*4096)/(fith-1):0;
   expected_sum=0;
   for(oy=0;oy<OH;oy=oy+1)begin
    fileoy=td?oy:OH-1-oy;dy=fileoy-pady;
    for(ox=0;ox<OW;ox=ox+1)begin
     dx=ox-padx;result=0;
     if(dx>=0&&dx<fitw&&dy>=0&&dy<fith)begin
      cx=dx*stepx;cy=dy*stepy;
      sx=cx/4096;fx=(cx%4096)/16;sy=cy/4096;fy=(cy%4096)/16;
      if(fitw>1&&dx==fitw-1)begin sx=w-1;fx=0;end
      if(fith>1&&dy==fith-1)begin sy=h-1;fy=0;end
      sx1=sx<w-1?sx+1:sx;sy1=sy<h-1?sy+1:sy;
      y0=td?sy:h-1-sy;y1=td?sy1:h-1-sy1;
      for(ch=0;ch<3;ch=ch+1)begin
       a=lerp(source_channel(sx,y0,ch),source_channel(sx1,y0,ch),fx);
       b=lerp(source_channel(sx,y1,ch),source_channel(sx1,y1,ch),fx);
       result[ch*8+:8]=lerp(a,b,fy);
      end
     end
     gold[oy*OW+ox]=result;seen[oy*OW+ox]=0;expected_sum=expected_sum+result;
    end
   end
  end
 endtask
 task send_bytes;input integer count,expect_error;integer index;begin
  index=0;
  while(index<count&&!error)begin
   @(negedge clk);in_valid=lfsr[4]||lfsr[5];in_byte=bytes[index];in_last=index==count-1;
   @(posedge clk);if(in_valid&&in_ready)index=index+1;
  end
  @(negedge clk);in_valid=0;in_last=0;
  if(expect_error)begin wait(error);if(code!==expect_error[7:0])$fatal(1,"wrong error %h",code);end
  else begin
   wait(done||error);if(error)$fatal(1,"unexpected error %h",code);
   wait(!pvalid);@(negedge clk);
   if(pixels!=OW*OH||checksum!==expected_sum)$fatal(1,"count/checksum mismatch pixels=%0d sum=%h expected=%h",pixels,checksum,expected_sum);
  end
 end endtask
 task begin_case;input integer valid_case;begin
  check_pixels=0;@(negedge clk);begin_file=1;@(negedge clk);begin_file=0;
  pixels=0;tests=tests+1;check_pixels=valid_case;
 end endtask
 task good_case;input integer w,h,td,extra,trailer;begin
  prepare(w,h,td,extra,trailer);begin_case(1);send_bytes(file_size,0);
  if(sw!=w||sh!=h)$fatal(1,"source metadata mismatch");
  $display("case %0d passed source=%0dx%0d td=%0d fit=%0dx%0d",tests,w,h,td,fw,fh);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  if(OW==640&&OH==480)begin
   good_case(320,240,0,0,0);good_case(800,600,1,0,0);
   good_case(1024,768,0,0,0);good_case(321,241,1,16,0);
   good_case(480,640,0,0,0);
   $display("TEST PASS scaler_full: five native-size bilinear reference frames, real640x480 output, mixed source sizes, portrait bars, metadata and stalls");$finish;
  end
  good_case(8,6,0,0,0);good_case(8,6,1,32,17);
  good_case(3,2,0,0,0);good_case(3,2,1,4,5);
  good_case(12,9,0,0,0);good_case(7,11,1,0,0);
  good_case(11,7,0,8,0);good_case(1,1,0,0,0);
  good_case(1,7,1,0,0);good_case(8,1,0,0,0);
  good_case(321,241,0,0,0);good_case(1024,768,1,0,0);
  prepare(8,6,1,0,0);put32(18,1025);begin_case(0);send_bytes(file_size,8'h21);
  prepare(8,6,1,0,0);put32(22,0);begin_case(0);send_bytes(file_size,8'h21);
  prepare(8,6,1,0,0);put32(30,1);begin_case(0);send_bytes(file_size,8'h21);
  prepare(8,6,1,0,0);bytes[28]=16;begin_case(0);send_bytes(file_size,8'h21);
  prepare(8,6,1,0,0);put32(2,file_size-1);begin_case(0);send_bytes(file_size,8'h21);
  prepare(8,6,1,0,0);begin_case(0);send_bytes(100,8'h22);
  good_case(2,3,0,0,0);
  $display("TEST PASS scaler: %0d cases, bilinear reference pixels/blackbars, two-row maximum dimensions, stalls, malformed/truncated files and recovery",tests);$finish;
 end
 initial begin #1000000000;$fatal(1,"scaler timeout state=%d pos=%d",dut.state,dut.pos);end
endmodule
