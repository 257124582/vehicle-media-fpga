`timescale 1ns/1ps
// Original project RTL. Asynchronous assertion, synchronous release.
(* keep_hierarchy="true" *) module reset_sync(input clk,input arst,output rst);
 // TD's documented preserve/keep attributes prevent reset-stage merging
 // into unrelated logic, preserving both CDC structure and narrow SR exceptions.
 (* preserve=1, keep=1, async_reg="true" *) reg [2:0] pipe;
 always @(posedge clk or posedge arst) if(arst) pipe<=3'b111; else pipe<={pipe[1:0],1'b0};
 assign rst=pipe[2];
endmodule

// Bundled-data mailbox. The source holds payload until the returning acknowledgement.
module cdc_mailbox #(parameter WIDTH=32)(
 input sclk,input srst,input [WIDTH-1:0] sdata,input send,output busy,
 input dclk,input drst,output reg [WIDTH-1:0] ddata,output reg valid);
 reg request,ack; reg [WIDTH-1:0] held;
 (* async_reg="true" *) reg [1:0] ack_sync,req_sync;
 assign busy=request!=ack_sync[1];
 always @(posedge sclk or posedge srst) begin
  if(srst) begin request<=0;held<=0;ack_sync<=0;end
  else begin ack_sync<={ack_sync[0],ack}; if(send&&!busy) begin held<=sdata;request<=~request;end end
 end
 always @(posedge dclk or posedge drst) begin
  if(drst) begin req_sync<=0;ack<=0;ddata<=0;valid<=0;end
  else begin req_sync<={req_sync[0],request};valid<=0;
   if(req_sync[1]!=ack) begin ddata<=held;valid<=1;ack<=req_sync[1];end
  end
 end
endmodule

module key_debounce #(parameter CYCLES=500000)(input clk,input rst,input key_n,output reg press);
 (* async_reg="true" *) reg [1:0] sync;
 reg stable;reg [23:0] count;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sync<=3;stable<=1;count<=0;press<=0;end
  else begin sync<={sync[0],key_n};press<=0;
   if(sync[1]==stable) count<=0;
   else if(count==CYCLES-1) begin stable<=sync[1];count<=0;press<=!sync[1];end
   else count<=count+1'b1;
  end
 end
endmodule

// Registered read, Gray pointers. Depth is 2**AW; occupancy is in write domain.
module async_fifo #(parameter WIDTH=24,parameter AW=11)(
 input wclk,input wrst,input we,input [WIDTH-1:0] wdata,output full,output [AW:0] used,
 input rclk,input rrst,input re,output reg [WIDTH-1:0] rdata,output empty);
 reg [WIDTH-1:0] mem[0:(1<<AW)-1];
 reg [AW:0] wb,rb,wg,rg;
 (* async_reg="true" *) reg [AW:0] rg1,rg2,wg1,wg2;
 function [AW:0] ungray;input [AW:0] g;integer i;begin
  ungray[AW]=g[AW];for(i=AW-1;i>=0;i=i-1) ungray[i]=ungray[i+1]^g[i];end endfunction
 assign full=wg=={~rg2[AW:AW-1],rg2[AW-2:0]};
 assign empty=rg==wg2;
 assign used=wb-ungray(rg2);
 always @(posedge wclk or posedge wrst) begin
  if(wrst) begin wb<=0;wg<=0;rg1<=0;rg2<=0;end
  else begin rg1<=rg;rg2<=rg1;
   if(we&&!full) begin mem[wb[AW-1:0]]<=wdata;wb<=wb+1'b1;wg<=((wb+1'b1)>>1)^(wb+1'b1);end
  end
 end
 always @(posedge rclk or posedge rrst) begin
  if(rrst) begin rb<=0;rg<=0;wg1<=0;wg2<=0;rdata<=0;end
  else begin wg1<=wg;wg2<=wg1;
   if(re&&!empty) begin rdata<=mem[rb[AW-1:0]];rb<=rb+1'b1;rg<=((rb+1'b1)>>1)^(rb+1'b1);end
  end
 end
endmodule

module spi_byte(input clk,input rst,input start,input [7:0] tx,input [15:0] half_period,
 input miso,output reg sck,output reg mosi,output reg busy,output reg done,output reg [7:0] rx);
 reg [15:0] ticks;reg [3:0] bit_no;reg [7:0] shift_tx,shift_rx;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sck<=0;mosi<=1;busy<=0;done<=0;rx<=0;ticks<=0;bit_no<=0;shift_tx<=0;shift_rx<=0;end
  else begin done<=0;
   if(!busy) begin sck<=0;
    if(start) begin busy<=1;shift_tx<=tx;mosi<=tx[7];shift_rx<=0;bit_no<=0;ticks<=0;end
   end else if(ticks==half_period-1) begin
    ticks<=0;sck<=~sck;
    if(!sck) shift_rx<={shift_rx[6:0],miso};
    else if(bit_no==7) begin busy<=0;done<=1;rx<=shift_rx;mosi<=1;end
    else begin bit_no<=bit_no+1'b1;shift_tx<={shift_tx[6:0],1'b1};mosi<=shift_tx[6];end
   end else ticks<=ticks+1'b1;
  end
 end
endmodule
