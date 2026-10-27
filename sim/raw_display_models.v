`timescale 1ns/1ps
// Explicit raw-pixel regression bypasses. The real media_osd and waveform RTL
// are exercised together in tb_extensions_system and separately in tb_osd /
// tb_audio_visualizer. No display text is needed for FAT/cache pixel matching.
module media_osd #(parameter CLOCK_HZ=25000000)(
 input clk,input rst,input frame_tick,input de,input [10:0] x,input [9:0] y,
 input [23:0] rgb,input [2:0] image_count,input [1:0] image,input [2:0] mode,
 input autoplay,input signed [8:0] brightness,input [9:0] contrast,input [3:0] volume,
 input menu_active,input [2:0] menu_item,input ticker_enable,input wave_enable,
 input continuous_audio,input [15:0] source_width,input [15:0] source_height,
 input [7:0] error_code,input wave_pixel,output [23:0] out_rgb,input overlay_enable,input transition_enable,input night_mode);
 assign out_rgb=rgb;
endmodule
module audio_visualizer #(parameter SAMPLES_PER_COLUMN=4,X_START=64,Y_CENTER=378)(
 input clk,input rst,input frame_tick,input audio_valid,input signed [23:0] pcm,
 input enable,input [10:0] x,input [9:0] y,output wave_pixel);
 assign wave_pixel=1'b0;
endmodule
