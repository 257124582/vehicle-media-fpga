`timescale 1ns/1ps
module tb_adaptive;
 reg clk=0;always #20 clk=~clk;reg rst=1,de=0;reg [10:0] x=0;reg [9:0] y=12;
 wire ode;wire [10:0] ox;wire [9:0] oy;wire [23:0] rgb;wire [7:0] mean;wire [2:0] mode;
 integer frame=0,seen=0,xx,yy;
 image_pipeline #(.WIDTH(16),.HEIGHT(12),.HTOTAL(24)) dut(clk,rst,de,x,y,24'h323232,
  3'd2,8'd128,9'sd0,10'd256,5'd16,1'b0,1'b1,ode,ox,oy,rgb,mean,mode);
 always @(negedge clk)if(ode)begin
  if(rgb!==(frame==0?24'h000000:24'hffffff))$fatal(1,"adaptive threshold frame %d got %h mean %d",frame,rgb,mean);
  seen=seen+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;repeat(48)@(negedge clk);
  for(frame=0;frame<2;frame=frame+1)begin
   seen=0;for(yy=0;yy<12;yy=yy+1)for(xx=0;xx<24;xx=xx+1)begin x=xx;y=yy;de=xx<16;@(negedge clk);end
   de=0;repeat(96)@(negedge clk);if(seen!=192||mean!=50)$fatal(1,"mean/count");
  end
  $display("TEST PASS adaptive: previous-frame measured mean becomes next frame threshold");$finish;
 end
endmodule
