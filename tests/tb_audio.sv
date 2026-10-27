`timescale 1ns/1ps
module tb_audio;
 reg clk=0;always #20 clk=~clk;reg rst=1,trigger=0;reg [1:0] image=0;reg [3:0] volume=15;
 wire valid,acr;wire signed [23:0] left,right;wire [19:0] cts,n;
 audio_pcm dut(clk,rst,trigger,image,volume,valid,left,right,acr,cts,n,1'b0);
 integer samples=0,acrs=0,crossings=0,silent=0;reg signed [23:0] prior=0;
 always @(negedge clk)if(!rst)begin
  if(valid)begin
   samples=samples+1;if(left!==right)$fatal(1,"channels differ");
   if(left>8000000||left< -8000000)$fatal(1,"clipping");
   if(samples>256&&samples<23744&&left>=0&&prior<0)crossings=crossings+1;
   if(samples>24100&&left!=0)$fatal(1,"envelope did not finish");
   prior=left;
  end
  if(acr)begin acrs=acrs+1;if(cts!=25000||n!=6144)$fatal(1,"ACR mismatch cts=%d n=%d",cts,n);end
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;trigger=1;@(negedge clk);trigger=0;
  repeat(25000000)@(negedge clk);
  if(samples!=48000||acrs!=999||crossings<212||crossings>219)$fatal(1,"rate/tone mismatch samples=%d acrs=%d crossings=%d",samples,acrs,crossings);
  $display("TEST PASS audio: 48000 samples/s, 999 measured ACRs, 440Hz crossings=%d, 0.5s envelope and zero PCM tail",crossings);$finish;
 end
endmodule
