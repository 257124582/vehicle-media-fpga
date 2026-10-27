`timescale 1ns/1ps
module tb_faults;
 reg clk=0;always #4 clk=~clk;reg rst=1,start=0;wire req;wire [31:0] lba;reg ready=1,bv=0,done=0,failed=0;
 reg [8:0] bi=0;reg [7:0] data=0;wire fb,fv,fl,fr;wire [31:0] size;wire [1:0] slot;wire [7:0] byte_data;
 wire pv,pl,bd,be;wire [23:0] rgb;wire [20:0] address;wire [7:0] bcode;wire [31:0] sum;
 wire [2:0] count;wire complete;wire [7:0] error,state;wire [15:0] skipped;reg wrote=0;
 fat32_media fat(clk,rst,start,req,lba,ready,bv,bi,data,done,failed,fb,size,slot,fv,byte_data,fl,fr,
  be||(bd&&wrote&&!pv),!be,count,complete,error,skipped,state);
 bmp_stream bmp(clk,rst,fb,size,fv,byte_data,fl,fr,pv,rgb,address,pl,1'b1,bd,be,bcode,sum,,,,);
 reg [7:0] sector[0:511];integer fd,rc,idx=-1;string path;integer expected=0;
 initial begin
  if(!$value$plusargs("IMAGE=%s",path))$fatal(1,"IMAGE required");rc=$value$plusargs("ERROR=%h",expected);
  fd=$fopen(path,"rb");if(!fd)$fatal(1,"fixture missing");repeat(8)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 end
 always @(posedge clk)begin
  bv<=0;done<=0;
  if(req)begin rc=$fseek(fd,lba*512,0);rc=$fread(sector,fd);if(rc!=512)$fatal(1,"outside card");idx=0;ready<=0;end
  else if(idx>=0)begin bv<=1;bi<=idx;data<=sector[idx];if(idx==511)begin idx=-1;done<=1;ready<=1;end else idx=idx+1;end
  if(fb)wrote<=0;if(pv&&pl)wrote<=1;
  if(complete)begin
   if(expected==8'h11)begin if(count!=0||error!=8'h11)$fatal(1,"invalid BPB accepted");end
   else if(count!=3||skipped!=2||error!=expected)$fatal(1,"chain rejection failed count=%d skipped=%d error=%h expected=%h",count,skipped,error,expected);
   $display("TEST PASS faults: expected %h count=%d skipped=%d",error,count,skipped);$finish;
  end
 end
 initial begin #1000000000;$fatal(1,"fault test hung state=%d",state);end
endmodule
