`timescale 1ns/1ps
module video_raster #(parameter HTOTAL=800,VTOTAL=525,WIDTH=640,HEIGHT=480)(
 input clk,input rst,output reg [10:0] x,output reg [9:0] y,output de,output frame_tick);
 assign de=x<WIDTH&&y<HEIGHT;
 assign frame_tick=x==0&&y==HEIGHT;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=HEIGHT;end
  else if(x==HTOTAL-1)begin x<=0;if(y==VTOTAL-1)y<=0;else y<=y+1'b1;end
  else x<=x+1'b1;
 end
endmodule

// Continuous-raster delay equals one full line plus one pixel and one pipeline register.
// Border pixels of Sobel are zero. The original/other modes use the aligned centre RGB.
module image_pipeline #(parameter WIDTH=640,HEIGHT=480,HTOTAL=800)(
 input clk,input rst,input in_de,input [10:0] in_x,input [9:0] in_y,input [23:0] in_rgb,
 input [2:0] mode,input [7:0] threshold,input signed [8:0] brightness,input [9:0] contrast,
 input [4:0] alpha,input compare,input adaptive,
 output reg out_de,output reg [10:0] out_x,output reg [9:0] out_y,output reg [23:0] out_rgb,
 output reg [7:0] mean_gray,output reg [2:0] active_mode);
 localparam DELAY=HTOTAL+1;
 reg [9:0] delay_ptr;reg [11:0] warm;
 wire [47:0] delay_q;wire [45:0] delayed=delay_q[45:0];
 wire [23:0] prev1,prev2;reg [23:0] current;
 reg valid1;reg [10:0] x1;reg [9:0] y1;
 reg [7:0] t1,t2,m1,m2,b1,b2;
 reg [7:0] thresh_latch;reg signed [8:0] bright_latch;reg [9:0] contrast_latch;reg [4:0] alpha_latch;
 reg compare_latch,adaptive_latch;
 wire d_de=delayed[45];wire [10:0] dx=delayed[44:34];wire [9:0] dy=delayed[33:24];wire [23:0] raw=delayed[23:0];
 wire first=d_de&&dx==0&&dy==0;
 wire [2:0] use_mode=first?mode:active_mode;
 wire [7:0] use_threshold=first?(adaptive?mean_gray:threshold):thresh_latch;
 wire signed [8:0] use_brightness=first?brightness:bright_latch;
 wire [9:0] use_contrast=first?contrast:contrast_latch;
 wire [4:0] use_alpha=first?alpha:alpha_latch;
 wire use_compare=first?compare:compare_latch;
 function [7:0] luminance;input [23:0] rgb;reg [17:0] s;begin
  s=77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0]+128;luminance=s>>8;end endfunction
 function [7:0] saturate;input signed [20:0] v;begin if(v<0)saturate=0;else if(v>255)saturate=255;else saturate=v[7:0];end endfunction
 function [7:0] change;input [7:0] v;input [2:0] md;input signed [8:0] br;input [9:0] co;
  reg signed [20:0] s;begin
   if(md==4)s=$signed({1'b0,v})+br;
   else s=(($signed({1'b0,v})-21'sd128)*$signed({1'b0,co})>>>8)+21'sd128;
   change=saturate(s);end endfunction
 wire [7:0] gt=luminance(prev2),gm=luminance(prev1),gb=luminance(current),gy=luminance(raw);
 reg signed [12:0] gx,sy;reg [12:0] mag;reg [7:0] edge_value;reg [23:0] selected;
 reg [12:0] scaled_r,scaled_g,scaled_b;
 reg [26:0] sum_gray;reg [31:0] dividend,quotient;reg [19:0] remainder;
 reg [5:0] divide_count;reg dividing;reg [20:0] trial;
 always @* begin
  gx=$signed({1'b0,gt})+2*$signed({1'b0,gm})+$signed({1'b0,gb})-
     $signed({1'b0,t1})-2*$signed({1'b0,m1})-$signed({1'b0,b1});
  sy=$signed({1'b0,b1})+2*$signed({1'b0,b2})+$signed({1'b0,gb})-
     $signed({1'b0,t1})-2*$signed({1'b0,t2})-$signed({1'b0,gt});
  mag=(gx<0?-gx:gx)+(sy<0?-sy:sy);
  edge_value=(mag>>2)>255?255:mag>>2;
  if(dx==0||dy==0||dx==WIDTH-1||dy==HEIGHT-1||!valid1)edge_value=0;
  case(use_mode)
   0:selected=raw;
   1:selected={gy,gy,gy};
   2:selected=gy>=use_threshold?24'hffffff:24'h000000;
   3:selected={edge_value,edge_value,edge_value};
   4,5:selected={change(raw[23:16],use_mode,use_brightness,use_contrast),
    change(raw[15:8],use_mode,use_brightness,use_contrast),change(raw[7:0],use_mode,use_brightness,use_contrast)};
   default:selected=raw;
  endcase
  if(use_compare&&dx<WIDTH/2)selected=raw;
  if(use_compare&&dx==WIDTH/2)selected=24'h00ff80;
  scaled_r=selected[23:16]*use_alpha;scaled_g=selected[15:8]*use_alpha;scaled_b=selected[7:0]*use_alpha;
  trial={remainder,dividend[31]};
 end
 wire [47:0] delay_d={2'b0,in_de,in_x,in_y,in_rgb};
 genvar bank;
 generate for(bank=0;bank<3;bank=bank+1)begin:g_delay
  sync_image_ram #(.DW(16)) u_ram(clk,1'b1,delay_ptr,delay_d[bank*16+:16],delay_ptr,delay_q[bank*16+:16]);
 end endgenerate
 sync_image_ram #(.DW(24)) u_line1(clk,in_de,in_x[9:0],in_rgb,in_x[9:0],prev1);
 sync_image_ram #(.DW(24)) u_line2(clk,valid1,x1[9:0],prev1,in_x[9:0],prev2);
 always @(posedge clk)if(in_de)current<=in_rgb;
 always @(posedge clk or posedge rst)begin
  if(rst)begin delay_ptr<=0;warm<=0;valid1<=0;x1<=0;y1<=0;t1<=0;t2<=0;m1<=0;m2<=0;b1<=0;b2<=0;
   active_mode<=0;thresh_latch<=128;bright_latch<=0;contrast_latch<=256;alpha_latch<=16;compare_latch<=0;adaptive_latch<=0;
   out_de<=0;out_x<=0;out_y<=0;out_rgb<=0;mean_gray<=128;sum_gray<=0;
   dividend<=0;quotient<=0;remainder<=0;divide_count<=0;dividing<=0;
  end else begin
   if(delay_ptr==DELAY-1)delay_ptr<=0;else delay_ptr<=delay_ptr+1'b1;
   if(warm<DELAY+2)warm<=warm+1'b1;
   valid1<=in_de;x1<=in_x;y1<=in_y;
   if(valid1)begin t1<=t2;t2<=gt;m1<=m2;m2<=gm;b1<=b2;b2<=gb;end
   out_de<=d_de&&warm>=DELAY+1;out_x<=dx;out_y<=dy;
   out_rgb<={scaled_r[11:4],scaled_g[11:4],scaled_b[11:4]};
   if(first&&warm>=DELAY+1)begin
    active_mode<=mode;thresh_latch<=adaptive?mean_gray:threshold;bright_latch<=brightness;
    contrast_latch<=contrast;alpha_latch<=alpha;compare_latch<=compare;adaptive_latch<=adaptive;
   end
   if(d_de&&warm>=DELAY+1)begin
    if(first)sum_gray<=gy;else sum_gray<=sum_gray+gy;
    if(dx==WIDTH-1&&dy==HEIGHT-1)begin
     dividend<=sum_gray+gy;quotient<=0;remainder<=0;divide_count<=32;dividing<=1;
    end
   end
   if(dividing)begin
    dividend<=dividend<<1;quotient<=quotient<<1;
    if(trial>=WIDTH*HEIGHT)begin remainder<=trial-WIDTH*HEIGHT;quotient<=(quotient<<1)|1'b1;end
    else remainder<=trial;
    divide_count<=divide_count-1'b1;
    if(divide_count==1)begin dividing<=0;mean_gray<={quotient[6:0],trial>=WIDTH*HEIGHT};end
   end
  end
 end
endmodule

module sync_image_ram #(parameter DW=16,AW=10)(input clk,input we,input [AW-1:0] wa,
 input [DW-1:0] data,input [AW-1:0] ra,output reg [DW-1:0] q);
 (* ram_style="bram" *)reg [DW-1:0] memory[0:(1<<AW)-1];
 always @(posedge clk)if(we)memory[wa]<=data;
 always @(posedge clk)q<=memory[ra];
endmodule

