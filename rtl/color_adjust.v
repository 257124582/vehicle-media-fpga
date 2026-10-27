`timescale 1ns/1ps
// Global brightness/contrast after the selected filter. Three pipeline clocks;
// update settings at the first displayed pixel, and align all raster metadata.
module color_adjust(input clk,input rst,input de,input [10:0] x,input [9:0] y,input [23:0] rgb,
 input signed [8:0] brightness,input [9:0] contrast,input bypass,input [4:0] alpha,
 output reg out_de,output reg [10:0] out_x,output reg [9:0] out_y,output reg [23:0] out_rgb);
 reg signed [8:0] br_latch;reg [9:0] co_latch;reg bypass_latch;reg [4:0] alpha_latch;
 wire first=de&&x==0&&y==0;
 wire signed [8:0] br=first?brightness:br_latch;
 wire [9:0] co=first?contrast:co_latch;
 wire bp=first?bypass:bypass_latch;
 wire [4:0] a=first?alpha:alpha_latch;
 reg signed [20:0] r_product,g_product,b_product;reg signed [8:0] br1;
 reg de1,bp1;reg [10:0] x1;reg [9:0] y1;reg [23:0] rgb1;
 reg de2;reg [10:0] x2;reg [9:0] y2;reg [23:0] rgb2;reg [4:0] a1,a2;
 wire [12:0] fade_r=rgb2[23:16]*a2,fade_g=rgb2[15:8]*a2,fade_b=rgb2[7:0]*a2;
 function [7:0] clip;input signed [20:0] v;begin clip=v<0?0:v>255?255:v[7:0];end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin br_latch<=0;co_latch<=256;bypass_latch<=0;alpha_latch<=16;br1<=0;
   de2<=0;x2<=0;y2<=0;rgb2<=0;a1<=16;a2<=16;
   r_product<=0;g_product<=0;b_product<=0;de1<=0;bp1<=0;x1<=0;y1<=0;rgb1<=0;
   out_de<=0;out_x<=0;out_y<=0;out_rgb<=0;
  end else begin
   if(first)begin br_latch<=brightness;co_latch<=contrast;bypass_latch<=bypass;alpha_latch<=alpha;end
   r_product<=($signed({1'b0,rgb[23:16]})-21'sd128)*$signed({1'b0,co});
   g_product<=($signed({1'b0,rgb[15:8]})-21'sd128)*$signed({1'b0,co});
   b_product<=($signed({1'b0,rgb[7:0]})-21'sd128)*$signed({1'b0,co});
   br1<=br;bp1<=bp;de1<=de;x1<=x;y1<=y;rgb1<=rgb;a1<=a;
   de2<=de1;x2<=x1;y2<=y1;a2<=a1;
   rgb2<=bp1?rgb1:{clip((r_product>>>8)+21'sd128+br1),
    clip((g_product>>>8)+21'sd128+br1),clip((b_product>>>8)+21'sd128+br1)};
   out_de<=de2;out_x<=x2;out_y<=y2;out_rgb<={fade_r[11:4],fade_g[11:4],fade_b[11:4]};
  end
 end
endmodule
