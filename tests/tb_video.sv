`timescale 1ns/1ps
module tb_video;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,de=0;reg [10:0] x=0;reg [9:0] y=480;reg [23:0] rgb=0;
 reg [2:0] mode=0;reg signed [8:0] brightness=32;reg [4:0] alpha=16;reg compare=0;
 wire ode;wire [10:0] ox;wire [9:0] oy;wire [23:0] result;wire [7:0] mean;wire [2:0] active;
 reg [23:0] source[0:307199],gold[0:307199];integer seen=0,md,xx,yy;reg checking=0;
 image_pipeline dut(clk,rst,de,x,y,rgb,mode,8'd128,brightness,10'd384,alpha,compare,1'b0,ode,ox,oy,result,mean,active);
 always @(negedge clk)if(checking&&ode)begin
  if(ox>=640||oy>=480)$fatal(1,"bad coordinate");
  if(oy*640+ox!=seen)$fatal(1,"raster sequence %d expected %d",oy*640+ox,seen);
  if(result!==gold[seen])$fatal(1,"mode=%d at %d,%d got=%h expected=%h",md,ox,oy,result,gold[seen]);
  seen=seen+1;
 end
 initial begin
  $readmemh("assets/reference/01_DAY.hex",source);
  for(md=0;md<8;md=md+1)begin
   checking=0;rst=1;de=0;mode=md<6?md:md==6?4:1;
   brightness=md==6?-64:32;alpha=md==7?8:16;compare=md==7;repeat(5)@(negedge clk);rst=0;
   $readmemh($sformatf("assets/reference/video_mode%0d.hex",md),gold);
   repeat(2400)@(negedge clk);seen=0;checking=1;
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<800;xx=xx+1)begin
    // Parameters written during a frame take effect only at the next first pixel.
    if(yy==100&&xx==0)begin mode=5;brightness=127;alpha=0;compare=0;end
    x=xx;y=yy;de=xx<640;rgb=xx<640?source[yy*640+xx]:0;@(negedge clk);
   end
   de=0;repeat(1800)@(negedge clk);
   if(seen!=307200)$fatal(1,"missing pixels %d",seen);
   $display("MODE PASS %0d mean=%0d",md,mean);
  end
  $display("TEST PASS video: eight full 640x480 frames, six modes, negative brightness, alpha/compare, frame-latched settings, Sobel borders, exact pixels/coordinates");$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
