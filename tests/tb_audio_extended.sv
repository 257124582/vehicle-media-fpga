`timescale 1ns/1ps
module tb_audio_extended;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,trigger=0,continuous_test=1;
 reg [1:0] image=0;reg [3:0] volume=15;
 wire valid,acr;wire signed [23:0] left,right;wire [19:0] cts,n;
 audio_pcm #(.CLK_HZ(480000)) dut(clk,rst,trigger,image,volume,valid,left,right,acr,cts,n,continuous_test);
 integer sample_count=0,acr_count=0,clock_count=0;
 integer crossings=0,window_count=0,minimum,maximum;
 reg signed [23:0] prior=0;
 reg count_crossings=0;
 always @(negedge clk)if(!rst)begin
  clock_count=clock_count+1;
  if(valid)begin
   sample_count=sample_count+1;
   if(left!==right)$fatal(1,"stereo PCM differs");
   if(left>8000000||left< -8000000)$fatal(1,"PCM clipping");
   if(count_crossings)begin
    window_count=window_count+1;
    if(left>=0&&prior<0)crossings=crossings+1;
   end
   prior=left;
  end
  if(acr)begin
   acr_count=acr_count+1;
   if(cts!=480||n!=6144)$fatal(1,"48 kHz ACR changed cts=%d n=%d",cts,n);
  end
 end
 task wait_samples(input integer count);
  integer target;
  begin target=sample_count+count;while(sample_count<target)@(negedge clk);end
 endtask
 task tone_window(input [1:0] which,input integer expected_crossings);
  begin
   image=which;wait_samples(512);
   crossings=0;window_count=0;count_crossings=1;
   wait_samples(12000);count_crossings=0;
   if(crossings<expected_crossings-2||crossings>expected_crossings+2)
    $fatal(1,"actual PCM frequency image=%d crossings=%d expected~%d",which,crossings,expected_crossings);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  wait_samples(25600);
  // Continuous mode must remain audible beyond the legacy half-second cue.
  minimum=0;maximum=0;
  repeat(1024)begin
   @(negedge clk);while(!valid)@(negedge clk);
   if(left<minimum)minimum=left;if(left>maximum)maximum=left;
  end
  if(minimum> -7000000||maximum<7000000)$fatal(1,"continuous test was silent or attenuated after 0.5s");
  tone_window(0,110);tone_window(1,138);tone_window(2,165);tone_window(3,220);
  volume=0;wait_samples(4);
  repeat(256)begin
   @(negedge clk);while(!valid)@(negedge clk);
   if(left!==0||right!==0)$fatal(1,"mute must emit exact zero PCM");
  end
  volume=8;wait_samples(512);minimum=0;maximum=0;
  repeat(512)begin
   @(negedge clk);while(!valid)@(negedge clk);
   if(left<minimum)minimum=left;if(left>maximum)maximum=left;
  end
  if(minimum< -4200000||maximum>4200000||minimum> -3700000||maximum<3700000)
   $fatal(1,"actual PCM volume scaling mismatch min=%d max=%d",minimum,maximum);
  continuous_test=0;wait_samples(3);
  repeat(96)begin
   @(negedge clk);while(!valid)@(negedge clk);
   if(left!==0)$fatal(1,"disabling continuous test did not stop tone");
  end
  if(sample_count!=clock_count/10)$fatal(1,"48k tick ratio changed samples=%d clocks=%d",sample_count,clock_count);
  if(acr_count<100)$fatal(1,"ACR checks were not exercised");
  $display("TEST PASS audio_extended: long continuous tone, actual PCM frequencies 440/550/660/880Hz, mute, volume and ACR");
  $finish;
 end
endmodule
