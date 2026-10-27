`timescale 1ns/1ps
module tb_cache;
 localparam W=640,H=480,F=W*H;
 reg clk=0,pclk=0;always #4 clk=~clk;always #20 pclk=~pclk;
 reg rst=1,begin_file=0,pv=0,pl=0,toggle=0,fetch=0;reg [23:0] rgb;reg [20:0] offset;
 wire pr,wc,ack,flush,full,we;wire [23:0] din,dout;wire [11:0] used;wire [31:0] wsum,rsum,timeouts;wire [7:0] fault;
 reg refreshing=0;wire awe,are,rv;wire [20:0] wa,ra;wire [31:0] wd,rd;wire [3:0] mask;wire rc;wire [1:0] rslot;
 frame_cache dut(clk,rst,begin_file,2'd2,pv,rgb,offset,pl,pr,wc,wsum,toggle,2'd2,fetch,ack,flush,used,full,we,din,
  1'b1,refreshing,1'b0,awe,wa,wd,mask,are,ra,rv,rd,timeouts,fault,rc,rsum,rslot);
 wire wrst,rrst,empty;reg re=0;reset_sync rw(clk,rst||flush,wrst);reset_sync rr(pclk,rst||flush,rrst);
 async_fifo fifo(clk,wrst,we,din,full,used,pclk,rrst,re,dout,empty);
 reg [31:0] memory[0:F*3-1];reg [9:0] latency;reg [20:0] address_pipe[0:9];integer k,counter=0,seen=0,xx,yy;reg check=0,consumed=0;
 reg [31:0] expected_sum=0;
 assign rv=latency[9];assign rd=memory[address_pipe[9]];
 function [23:0] pixel;input integer p;begin pixel=((p*1664525)^24'h718923)&24'hffffff;end endfunction
 always @(posedge clk)begin
  if(rst)begin latency<=0;counter<=0;refreshing<=0;end
  else begin
   counter<=counter+1;refreshing<=counter%1000>=970;
   if(awe&&are)$fatal(1,"overlapping write/read");
   if(awe)begin if(mask!=0||wa<F*2||wa>=F*3)$fatal(1,"bad write");memory[wa]<=wd;end
   latency<={latency[8:0],are};address_pipe[0]<=ra;
   for(k=1;k<10;k=k+1)address_pipe[k]<=address_pipe[k-1];
  end
 end
 always @(negedge pclk)begin
  if(check&&consumed)begin if(dout!==pixel(seen))$fatal(1,"FIFO order %d got %h",seen,dout);seen=seen+1;end
  re=check&&!empty&&!rrst&&seen<F;
 end
 always @(posedge pclk)consumed<=re&&!empty&&!rrst;
 initial begin
  repeat(8)@(negedge clk);rst=0;begin_file=1;@(negedge clk);begin_file=0;
  for(yy=H-1;yy>=0;yy=yy-1)for(xx=0;xx<W;xx=xx+1)begin
   offset=yy*W+xx;rgb=pixel(offset);expected_sum=expected_sum+rgb;pl=yy==0&&xx==W-1;pv=1;
   do @(posedge clk);while(!pr);
   @(negedge clk);pv=0;repeat(3)@(negedge clk);
  end
  wait(wc);if(wsum!==expected_sum)$fatal(1,"write sum");
  @(negedge clk);fetch=1;toggle=1;wait(ack);check=1;
  wait(seen==F);repeat(30)@(negedge clk);
  if(!rc||rsum!==expected_sum||rslot!=2||fault||timeouts)$fatal(1,"readback fault %h sum %h expected %h",fault,rsum,expected_sum);
  $display("TEST PASS cache: full bottom-up frame, aligned groups, 10-cycle SDRAM model, refresh pauses, dual-clock FIFO, 307200 readback pixels; sum=%h",rsum);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout seen=%d fault=%h",seen,fault);end
endmodule
