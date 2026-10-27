`timescale 1ns/1ps
module tb_vehicle_osd;
 reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,de=0,em=0,night=0,tech=0,arrival=0,menu=0,ready=1,ticker=1;
 reg [10:0] x=0;reg [9:0] y=0;reg [2:0] station=0;reg [3:0] item=0;reg [7:0] state=1;
 reg [23:0] rgb=0;wire ode;wire [10:0] ox;wire [9:0] oy;wire [23:0] out;
 reg [9:0] before_phase;reg [23:0] pixels[0:307199];integer frame,xx,yy,fd;string filename;
 vehicle_osd dut(clk,rst,tick,de,x,y,rgb,rgb,em,night,tech,station,arrival,menu,item,-9'sd48,10'd224,4'd8,
  ticker,1'b1,1'b0,1'b1,ready,state,3'd4,8'h12,1'b0,ode,ox,oy,out);
 initial begin
  $readmemh("assets/reference_extended/01_DAY.hex",pixels);
  repeat(3)@(negedge clk);rst=0;
  for(frame=0;frame<9;frame=frame+1)begin
   em=frame==3||frame==8;night=frame==1;menu=frame==4;arrival=frame==2;station=frame==5?5:1;ready=frame<6;state=frame==6?0:4;
   @(negedge clk);tick=1;@(negedge clk);tick=0;
   filename=$sformatf("vehicle_v3_%0d.out",frame);fd=$fopen(filename,"w");
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    @(negedge clk);de=1;x=xx;y=yy;rgb=pixels[yy*640+xx];@(posedge clk);#1;
    if(!ode||ox!=xx||oy!=yy||$isunknown(out))$fatal(1,"pixel alignment/unknown frame %d %d,%d",frame,xx,yy);
    if(xx==639&&yy==300&&em&&out!==24'ha81810)$fatal(1,"emergency layer priority");
    $fdisplay(fd,"%06x",out);
   end
   $fclose(fd);@(negedge clk);de=0;
  end
  before_phase=dut.ticker_phase;ticker=0;
  @(negedge clk);tick=1;@(negedge clk);tick=0;
  if(dut.ticker_phase!=before_phase)$fatal(1,"disabled ticker moved");
  em=0;menu=0;ready=1;
  @(negedge clk);tick=1;@(negedge clk);tick=0;
  de=1;x=0;y=450;@(posedge clk);#1;
  if(out!==24'h123045)$fatal(1,"disabled passenger ticker still drawn");
  ticker=1;@(negedge clk);tick=1;@(negedge clk);tick=0;
  if(dut.ticker_phase!=before_phase+1'b1)$fatal(1,"enabled ticker not advancing");
  $display("TEST PASS vehicle OSD: 9 rendered states, synchronous glyph and RGB metadata aligned, emergency over fault");$finish;
 end
endmodule
