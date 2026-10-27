`timescale 1ns/1ps
module status_segments(input clk,input rst,input [23:0] digits,output reg [7:0] seg_data,output reg [5:0] seg_sel);
 reg [14:0] divider;reg [2:0] scan;reg [3:0] digit;
 always @*begin
  digit=digits>>(scan*4);seg_sel=~(6'b1<<scan);
  case(digit)0:seg_data=8'hc0;1:seg_data=8'hf9;2:seg_data=8'ha4;3:seg_data=8'hb0;
   4:seg_data=8'h99;5:seg_data=8'h92;6:seg_data=8'h82;7:seg_data=8'hf8;
   8:seg_data=8'h80;9:seg_data=8'h90;10:seg_data=8'h88;11:seg_data=8'h83;
   12:seg_data=8'hc6;13:seg_data=8'ha1;14:seg_data=8'h86;default:seg_data=8'h8e;endcase
 end
 always @(posedge clk or posedge rst)if(rst)begin divider<=0;scan<=0;end
  else if(divider==24999)begin divider<=0;scan<=scan==5?0:scan+1'b1;end else divider<=divider+1'b1;
endmodule

// Compact hexadecimal dashboard, using a 5x7 font doubled in both directions.
module status_osd(input de,input [10:0] x,input [9:0] y,input [23:0] rgb,
 input [31:0] information,output reg [23:0] result);
 reg [34:0] glyph;reg [3:0] digit;reg dot;integer column,row,cell_index;
 function [34:0] font;input [3:0] n;begin
  case(n)
   0:font=35'b01110_10001_10011_10101_11001_10001_01110;
   1:font=35'b00100_01100_00100_00100_00100_00100_01110;
   2:font=35'b01110_10001_00001_00010_00100_01000_11111;
   3:font=35'b11110_00001_00001_01110_00001_00001_11110;
   4:font=35'b00010_00110_01010_10010_11111_00010_00010;
   5:font=35'b11111_10000_10000_11110_00001_00001_11110;
   6:font=35'b01110_10000_10000_11110_10001_10001_01110;
   7:font=35'b11111_00001_00010_00100_01000_01000_01000;
   8:font=35'b01110_10001_10001_01110_10001_10001_01110;
   9:font=35'b01110_10001_10001_01111_00001_00001_01110;
   10:font=35'b01110_10001_10001_11111_10001_10001_10001;
   11:font=35'b11110_10001_10001_11110_10001_10001_11110;
   12:font=35'b01111_10000_10000_10000_10000_10000_01111;
   13:font=35'b11110_10001_10001_10001_10001_10001_11110;
   14:font=35'b11111_10000_10000_11110_10000_10000_11111;
   15:font=35'b11111_10000_10000_11110_10000_10000_10000;
  endcase
 end endfunction
 always @*begin
  cell_index=x>>4;column=(x[3:0]>>1);row=(y-8)>>1;digit=information>>(4*(7-cell_index));glyph=font(digit);
  dot=column<5&&row>=0&&row<7?glyph[34-row*5-column]:0;
  result=rgb;
  if(de&&y<30&&x<128)begin result={rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2],2'b0};
   if(y>=8&&y<22&&dot)result=24'h40ffff;
  end
 end
endmodule

