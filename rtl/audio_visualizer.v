`timescale 1ns/1ps
// Oscilloscope layer, fed from the post-volume PCM sent to the HDMI core.
// All inputs share the pixel clock. A complete capture is exchanged only at
// frame_tick: the displayed RAM bank is never written during an active frame.
// wave_pixel has ONE pixel-clock of latency relative to x/y/enable. Delay the
// underlying RGB and video timing by the same clock before compositing it.
module audio_visualizer #(
 parameter SAMPLES_PER_COLUMN=4,
 parameter X_START=64,
 parameter Y_CENTER=378
)(input clk,input rst,input frame_tick,input audio_valid,input signed [23:0] pcm,
 input enable,input [10:0] x,input [9:0] y,output reg wave_pixel);
 // One simple dual-port RAM: 2 banks x 512 columns x (min,max signed 6 bits).
 // No memory reset loop: only a fully captured bank can become visible.
 reg [11:0] samples[0:1023];
 reg display_bank,display_valid,capture_ready;
 reg [8:0] column;
 reg [2:0] bucket_count;
 reg signed [5:0] bucket_min,bucket_max;
 wire signed [5:0] amplitude=pcm[23:18];
 wire signed [5:0] capture_min=bucket_count==0?amplitude:
  (amplitude<bucket_min?amplitude:bucket_min);
 wire signed [5:0] capture_max=bucket_count==0?amplitude:
  (amplitude>bucket_max?amplitude:bucket_max);
 wire in_columns=x>=X_START&&x<X_START+512;
 wire [8:0] read_column=x-X_START;
 reg [11:0] read_word;
 reg read_visible;
 reg [9:0] read_y;
 wire signed [5:0] shown_min=read_word[5:0];
 wire signed [5:0] shown_max=read_word[11:6];
 wire signed [10:0] low_y=Y_CENTER-$signed(shown_max);
 wire signed [10:0] high_y=Y_CENTER-$signed(shown_min);
 wire signed [10:0] pixel_y=$signed({1'b0,read_y});

 always @(posedge clk)begin
  read_word<=samples[{display_bank,in_columns?read_column:9'd0}];
  if(!rst&&audio_valid&&!capture_ready&&bucket_count==SAMPLES_PER_COLUMN-1)
   samples[{~display_bank,column}]<={capture_max,capture_min};
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   display_bank<=0;display_valid<=0;capture_ready<=0;column<=0;
   bucket_count<=0;bucket_min<=0;bucket_max<=0;read_visible<=0;read_y<=0;
  end else begin
   read_visible<=enable&&display_valid&&in_columns;
   read_y<=y;
   if(frame_tick&&capture_ready)begin
    display_bank<=~display_bank;display_valid<=1;capture_ready<=0;
    column<=0;bucket_count<=0;bucket_min<=0;bucket_max<=0;
   end else if(audio_valid&&!capture_ready)begin
    bucket_min<=capture_min;bucket_max<=capture_max;
    if(bucket_count==SAMPLES_PER_COLUMN-1)begin
     bucket_count<=0;
     if(column==511)capture_ready<=1;
     else column<=column+1'b1;
    end else bucket_count<=bucket_count+1'b1;
   end
  end
 end
 // A one-pixel border keeps zero/low-volume waveforms visible. This still
 // represents the PCM extrema; no independently generated sine is drawn.
 always @*begin
  wave_pixel=read_visible&&pixel_y>=low_y-1&&pixel_y<=high_y+1;
 end
endmodule
