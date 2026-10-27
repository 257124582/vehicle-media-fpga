`timescale 1ns/1ps
// Pixel-clock PCM, exact rational 48 kHz tick. No I2S loopback.
module audio_pcm #(parameter CLK_HZ=25000000)(input clk,input rst,input trigger,input [1:0] image,
 input [3:0] volume,output reg valid,output reg signed [23:0] left,output reg signed [23:0] right,
 output reg acr_valid,output reg [19:0] cts,output [19:0] n,input continuous_test);
 reg [25:0] rate;reg [31:0] phase,step;reg [14:0] remaining;reg [8:0] envelope;
 reg [5:0] block_count;reg [19:0] cts_count;reg cts_started;
 reg signed [16:0] triangle;reg signed [31:0] sample;
 assign n=20'd6144;
 always @*begin
  triangle=phase[31]?$signed({1'b0,~phase[30:15]})-17'sd32768:
   $signed({1'b0,phase[30:15]})-17'sd32768;
  sample=triangle*$signed({1'b0,envelope})*$signed({1'b0,volume});
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin rate<=0;phase<=0;step<=32'd39370534;remaining<=0;envelope<=0;
   valid<=0;left<=0;right<=0;acr_valid<=0;cts<=25000;block_count<=0;cts_count<=0;cts_started<=0;end
  else begin
   valid<=0;acr_valid<=0;cts_count<=cts_count+1'b1;
   if(trigger)begin remaining<=24000;phase<=0;envelope<=0;
    case(image)0:step<=39370534;1:step<=49213167;2:step<=59055800;3:step<=78741067;endcase
   end
   if(rate+48000>=CLK_HZ)begin
    rate<=rate+48000-CLK_HZ;valid<=1;
    // Max +/-7.86 million, within signed 24 bits; zero PCM remains continuous.
    // A separate test mode makes audio reception easy to check. Keep the
    // original half-second cue unchanged when this added input is low (or
    // omitted by an older testbench). Both paths use the same actual PCM.
    if(remaining!=0)begin left<=sample>>>4;right<=sample>>>4;end
    else if(continuous_test)begin left<=sample>>>4;right<=sample>>>4;end
    else begin left<=0;right<=0;end
    phase<=phase+step;
    if(continuous_test)begin
     case(image)0:step<=39370534;1:step<=49213167;2:step<=59055800;3:step<=78741067;endcase
     if(envelope<256)envelope<=envelope+1'b1;
     if(remaining!=0)remaining<=remaining-1'b1;
    end else if(remaining!=0)begin remaining<=remaining-1'b1;
     if(remaining>256)begin if(envelope<256)envelope<=envelope+1'b1;end
     else if(envelope!=0)envelope<=envelope-1'b1;
    end else envelope<=0;
    if(block_count==47)begin block_count<=0;cts_count<=0;
     if(cts_started)begin cts<=cts_count+1'b1;acr_valid<=1;end else cts_started<=1;
    end else block_count<=block_count+1'b1;
   end else rate<=rate+48000;
  end
 end
endmodule
