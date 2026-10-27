`timescale 1ns/1ps
module tb_vehicle_scene;
 reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,et=0,nt=0,cv=0;reg [4:0] cmd=0;reg signed [15:0] val=0;
 wire rv,re,em,night,tech,arrival,alert,at,held;wire [2:0] station;wire [31:0] ec,rc,lat;
 vehicle_scene #(.CLOCK_HZ(100)) dut(clk,rst,tick,et,nt,cv,cmd,val,rv,re,em,night,tech,station,arrival,alert,at,held,ec,rc,lat);
 wire pr,pe,rescan,autoplay,trans,compare,adaptive,audio,cont,ticker,wave;wire [1:0] img;wire [5:0] period;wire [2:0] mode;
 wire [7:0] thr;wire signed [8:0] br;wire [9:0] contrast;wire [3:0] volume;wire [4:0] alpha;
 reg pcv=0;reg [4:0] pcmd=0;reg signed [15:0] pval=0;
 playback_control #(.CLK_HZ(40)) ctrl(clk,rst,tick,3'd4,1'b1,1'b0,1'b0,1'b0,pcv,pcmd,pval,pr,pe,rescan,img,autoplay,period,mode,thr,br,contrast,volume,trans,compare,adaptive,alpha,audio,cont,ticker,wave,held,night);
 task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
 task send(input integer c,v,input bit bad);begin
  @(negedge clk);cv=1;cmd=c;val=v;@(negedge clk);cv=0;
  if(!rv||re!==bad)$fatal(1,"scene reply cmd %d val %d",c,v);
 end endtask
 task psend(input integer c,v,input bit bad);begin
  @(negedge clk);pcv=1;pcmd=c;pval=v;@(negedge clk);pcv=0;
  if(!pr||pe!==bad)$fatal(1,"play reply cmd %d val %d",c,v);
 end endtask
 reg [1:0] before_img,before_fade;reg [4:0] before_alpha;reg [24:0] before_counter;integer i,alert_count=0;
 always @(posedge clk)if(alert)alert_count=alert_count+1;
 initial begin
  repeat(3)@(negedge clk);rst=0;frame();
  send(19,5,0);frame();if(station!=5||!arrival)$fatal(1,"station/arrival");
  send(19,6,1);send(18,2,1);send(17,-1,1);send(20,2,1);send(21,0,0);
  psend(6,24,0);psend(7,320,0);
  send(18,1,0);frame();repeat(3)@(negedge clk);
  if(br!=-48||contrast!=224)$fatal(1,"night preset");
  psend(6,-60,0);send(18,0,0);frame();repeat(3)@(negedge clk);
  if(br!=24||contrast!=320)$fatal(1,"day bank");
  send(18,1,0);frame();repeat(3)@(negedge clk);if(br!=-60)$fatal(1,"night bank");
  for(i=0;i<100;i=i+1)begin
   psend(1,0,0);frame();repeat(i%18)frame();
   send(17,1,0);@(negedge clk);
   before_img=img;before_alpha=alpha;before_fade=ctrl.fading;before_counter=ctrl.second_counter;
   repeat(7)@(negedge clk);frame();
   if(!em||!held||lat>20)$fatal(1,"emergency latency/entry");
   psend(1,0,1);psend(2,0,1);psend(8,8,0);send(19,0,1);
   repeat(30)frame();
   if(img!=before_img||alpha!=before_alpha||ctrl.fading!=before_fade||ctrl.second_counter!=before_counter)$fatal(1,"playback not frozen");
   send(17,0,0);frame();if(em||held)$fatal(1,"resume");
  end
  if(ec!=100||rc!=100||alert_count!=100)$fatal(1,"event counts %d %d %d",ec,rc,alert_count);
  // Physical event wins when a UART command arrives on the same clock.
  @(negedge clk);et=1;cv=1;cmd=17;val=0;@(negedge clk);et=0;cv=0;frame();
  if(!em)$fatal(1,"physical emergency lost to UART");
  $display("TEST PASS vehicle scene: 100 preemptions, frozen transition/timer, recovery, presets, bounds, event priority");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
