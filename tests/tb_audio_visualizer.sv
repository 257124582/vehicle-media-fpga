`timescale 1ns/1ps
module tb_audio_visualizer;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,frame_tick=0,audio_valid=0,enable=1;
 reg signed [23:0] pcm=0;reg [10:0] x=64;reg [9:0] y=378;
 wire wave_pixel;
 audio_visualizer dut(clk,rst,frame_tick,audio_valid,pcm,enable,x,y,wave_pixel);
 task sample(input integer a);
  begin @(negedge clk);audio_valid=1;pcm=a*262144;@(negedge clk);audio_valid=0;end
 endtask
 task scan_pixel(input integer px,input integer py,input bit expected);
  begin
   @(negedge clk);x=px;y=py;@(negedge clk);
   if(wave_pixel!==expected)$fatal(1,"PCM waveform mismatch x=%d y=%d got=%b expected=%b",px,py,wave_pixel,expected);
  end
 endtask
 task swap;
  begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;end
 endtask
 integer c;
 initial begin
  repeat(5)@(negedge clk);rst=0;
  scan_pixel(64,378,0);
  // Extremes must include all four PCM samples, rather than decimating just
  // one or drawing a frequency-driven imitation of the audio signal.
  for(c=0;c<512;c=c+1)begin
   if(c%2==0)begin sample(0);sample(12);sample(-7);sample(3);end
   else begin sample(5);sample(5);sample(5);sample(5);end
  end
  scan_pixel(64,378,0); // a complete buffer still waits for frame boundary.
  swap();
  scan_pixel(64,366,1);scan_pixel(64,385,1);scan_pixel(64,365,1);
  scan_pixel(64,386,1);scan_pixel(64,364,0);scan_pixel(64,387,0);
  scan_pixel(65,373,1);scan_pixel(65,378,0);
  scan_pixel(63,378,0);scan_pixel(576,378,0);
  // Capture a mute window. The currently displayed trace must stay unchanged
  // through the whole capture and until the next frame starts.
  for(c=0;c<512;c=c+1)begin sample(0);sample(0);sample(0);sample(0);end
  scan_pixel(64,366,1);scan_pixel(65,373,1);
  sample(20);sample(-20); // frozen ready bank must ignore additional samples.
  swap();scan_pixel(64,378,1);scan_pixel(65,378,1);
  scan_pixel(64,366,0);scan_pixel(575,378,1);
  enable=0;scan_pixel(64,378,0);
  enable=1;scan_pixel(64,378,1);
  rst=1;@(negedge clk);rst=0;scan_pixel(64,378,0);
  $display("TEST PASS audio_visualizer: real PCM extrema, frame-stable double buffer, mute, bounds, enable and reset");
  $finish;
 end
endmodule
