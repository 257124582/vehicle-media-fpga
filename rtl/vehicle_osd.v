`timescale 1ns/1ps
module vehicle_osd(input clk,rst,frame_tick,de,input [10:0] x,input [9:0] y,
 input [23:0] rgb,legacy_rgb,input emergency,night,technical,input [2:0] station,
 input arrival,menu_active,input [3:0] menu_item,input signed [8:0] brightness,
 input [9:0] contrast,input [3:0] volume,input ticker,wave,continuous_audio,transition,
 input media_ready,input [7:0] media_state,input [2:0] count,input [7:0] error_code,
 input wave_pixel,output reg out_de,output reg [10:0] out_x,output reg [9:0] out_y,
 output [23:0] out_rgb);
 reg [9:0] ticker_phase;
 wire [10:0] ticker_position={1'b0,x[9:0]}+{1'b0,ticker_phase};
 reg menu_q,ready_q,ticker_q,wave_q,audio_q,transition_q;
 reg [3:0] item_q,volume_q;reg [7:0] state_q,error_q;reg [2:0] count_q;
 reg signed [8:0] bright_q;reg [9:0] contrast_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin ticker_phase<=0;menu_q<=0;ready_q<=0;item_q<=0;state_q<=0;error_q<=0;count_q<=0;
   bright_q<=0;contrast_q<=256;volume_q<=8;ticker_q<=1;wave_q<=1;audio_q<=0;transition_q<=1;end
  else if(frame_tick)begin if(ticker)ticker_phase<=ticker_phase+1'b1;menu_q<=menu_active;ready_q<=media_ready;
   item_q<=menu_item;state_q<=media_state;error_q<=error_code;count_q<=count;
   bright_q<=brightness;contrast_q<=contrast;volume_q<=volume;
   ticker_q<=ticker;wave_q<=wave;audio_q<=continuous_audio;transition_q<=transition;end
 end
function [7:0] phrase;input [4:0] row;input [5:0] col;begin
phrase=8'd32;case(row)
0:case(col)
0:phrase=8'd178;
1:phrase=8'd131;
2:phrase=8'd163;
3:phrase=8'd230;
4:phrase=8'd32;
5:phrase=8'd32;
6:phrase=8'd189;
7:phrase=8'd195;
endcase
1:case(col)
0:phrase=8'd152;
1:phrase=8'd118;
2:phrase=8'd196;
3:phrase=8'd231;
endcase
2:case(col)
0:phrase=8'd97;
1:phrase=8'd96;
2:phrase=8'd196;
3:phrase=8'd231;
endcase
3:case(col)
0:phrase=8'd199;
1:phrase=8'd190;
2:phrase=8'd196;
endcase
4:case(col)
0:phrase=8'd118;
1:phrase=8'd171;
2:phrase=8'd116;
3:phrase=8'd196;
4:phrase=8'd32;
5:phrase=8'd32;
6:phrase=8'd211;
7:phrase=8'd111;
8:phrase=8'd136;
9:phrase=8'd97;
10:phrase=8'd213;
endcase
5:case(col)
0:phrase=8'd198;
1:phrase=8'd154;
2:phrase=8'd166;
3:phrase=8'd195;
4:phrase=8'd32;
5:phrase=8'd32;
6:phrase=8'd211;
7:phrase=8'd105;
8:phrase=8'd161;
9:phrase=8'd110;
10:phrase=8'd224;
endcase
6:case(col)
0:phrase=8'd220;
1:phrase=8'd162;
2:phrase=8'd32;
3:phrase=8'd78;
4:phrase=8'd69;
5:phrase=8'd88;
6:phrase=8'd84;
7:phrase=8'd32;
8:phrase=8'd208;
9:phrase=8'd223;
10:phrase=8'd148;
11:phrase=8'd154;
endcase
7:case(col)
0:phrase=8'd182;
1:phrase=8'd214;
2:phrase=8'd100;
3:phrase=8'd213;
4:phrase=8'd32;
5:phrase=8'd32;
6:phrase=8'd183;
7:phrase=8'd133;
8:phrase=8'd115;
9:phrase=8'd139;
10:phrase=8'd121;
endcase
8:case(col)
0:phrase=8'd183;
1:phrase=8'd133;
2:phrase=8'd212;
3:phrase=8'd126;
4:phrase=8'd132;
5:phrase=8'd191;
endcase
9:case(col)
0:phrase=8'd172;
1:phrase=8'd127;
2:phrase=8'd192;
3:phrase=8'd132;
4:phrase=8'd191;
5:phrase=8'd32;
6:phrase=8'd32;
7:phrase=8'd211;
8:phrase=8'd179;
9:phrase=8'd177;
10:phrase=8'd124;
endcase
10:case(col)
0:phrase=8'd132;
1:phrase=8'd191;
2:phrase=8'd157;
3:phrase=8'd169;
4:phrase=8'd103;
5:phrase=8'd197;
6:phrase=8'd200;
7:phrase=8'd150;
8:phrase=8'd146;
endcase
11:case(col)
0:phrase=8'd141;
1:phrase=8'd107;
2:phrase=8'd124;
3:phrase=8'd212;
4:phrase=8'd126;
5:phrase=8'd150;
6:phrase=8'd146;
endcase
12:case(col)
0:phrase=8'd132;
1:phrase=8'd108;
2:phrase=8'd202;
3:phrase=8'd141;
4:phrase=8'd150;
5:phrase=8'd146;
endcase
13:case(col)
0:phrase=8'd206;
1:phrase=8'd123;
2:phrase=8'd99;
3:phrase=8'd217;
4:phrase=8'd160;
5:phrase=8'd218;
6:phrase=8'd170;
7:phrase=8'd158;
8:phrase=8'd165;
endcase
14:case(col)
0:phrase=8'd209;
1:phrase=8'd204;
2:phrase=8'd32;
3:phrase=8'd77;
4:phrase=8'd79;
5:phrase=8'd68;
6:phrase=8'd69;
7:phrase=8'd217;
8:phrase=8'd160;
9:phrase=8'd32;
10:phrase=8'd78;
11:phrase=8'd69;
12:phrase=8'd88;
13:phrase=8'd84;
14:phrase=8'd112;
15:phrase=8'd32;
16:phrase=8'd65;
17:phrase=8'd85;
18:phrase=8'd84;
19:phrase=8'd79;
20:phrase=8'd119;
endcase
15:case(col)
0:phrase=8'd220;
1:phrase=8'd162;
2:phrase=8'd77;
3:phrase=8'd79;
4:phrase=8'd68;
5:phrase=8'd69;
6:phrase=8'd215;
7:phrase=8'd130;
8:phrase=8'd32;
9:phrase=8'd125;
10:phrase=8'd168;
11:phrase=8'd137;
12:phrase=8'd104;
13:phrase=8'd129;
14:phrase=8'd155;
15:phrase=8'd137;
endcase
16:case(col)
0:phrase=8'd173;
1:phrase=8'd222;
endcase
17:case(col)
0:phrase=8'd138;
1:phrase=8'd222;
endcase
18:case(col)
0:phrase=8'd182;
1:phrase=8'd214;
2:phrase=8'd100;
3:phrase=8'd213;
4:phrase=8'd32;
5:phrase=8'd32;
6:phrase=8'd97;
7:phrase=8'd96;
8:phrase=8'd196;
9:phrase=8'd106;
10:phrase=8'd156;
11:phrase=8'd193;
12:phrase=8'd175;
13:phrase=8'd134;
14:phrase=8'd189;
15:phrase=8'd195;
16:phrase=8'd164;
17:phrase=8'd117;
endcase
endcase end endfunction
function [7:0] station_name;input [4:0] row;input [5:0] col;begin
station_name=8'd32;case(row)
0:case(col)
0:station_name=8'd98;
1:station_name=8'd221;
endcase
1:case(col)
0:station_name=8'd167;
1:station_name=8'd142;
2:station_name=8'd180;
endcase
2:case(col)
0:station_name=8'd132;
1:station_name=8'd101;
2:station_name=8'd229;
endcase
3:case(col)
0:station_name=8'd228;
1:station_name=8'd135;
endcase
4:case(col)
0:station_name=8'd143;
1:station_name=8'd205;
2:station_name=8'd122;
endcase
5:case(col)
0:station_name=8'd207;
1:station_name=8'd221;
endcase
endcase end endfunction
function [7:0] menu_label;input [4:0] row;input [5:0] col;begin
menu_label=8'd32;case(row)
0:case(col)
0:menu_label=8'd102;
1:menu_label=8'd149;
endcase
1:case(col)
0:menu_label=8'd144;
1:menu_label=8'd184;
2:menu_label=8'd149;
3:menu_label=8'd194;
4:menu_label=8'd114;
5:menu_label=8'd184;
endcase
2:case(col)
0:menu_label=8'd225;
1:menu_label=8'd219;
endcase
3:case(col)
0:menu_label=8'd188;
1:menu_label=8'd120;
2:menu_label=8'd140;
3:menu_label=8'd147;
endcase
4:case(col)
0:menu_label=8'd225;
1:menu_label=8'd227;
2:menu_label=8'd185;
3:menu_label=8'd153;
endcase
5:case(col)
0:menu_label=8'd216;
1:menu_label=8'd201;
2:menu_label=8'd186;
3:menu_label=8'd210;
4:menu_label=8'd225;
endcase
6:case(col)
0:menu_label=8'd187;
1:menu_label=8'd109;
2:menu_label=8'd187;
3:menu_label=8'd113;
endcase
7:case(col)
0:menu_label=8'd152;
1:menu_label=8'd118;
2:menu_label=8'd196;
3:menu_label=8'd203;
4:menu_label=8'd128;
endcase
8:case(col)
0:menu_label=8'd174;
1:menu_label=8'd138;
2:menu_label=8'd181;
3:menu_label=8'd151;
endcase
9:case(col)
0:menu_label=8'd159;
1:menu_label=8'd176;
2:menu_label=8'd145;
3:menu_label=8'd195;
4:menu_label=8'd226;
endcase
10:case(col)
0:menu_label=8'd148;
1:menu_label=8'd154;
2:menu_label=8'd189;
3:menu_label=8'd195;
endcase
11:case(col)
0:menu_label=8'd218;
1:menu_label=8'd170;
2:menu_label=8'd158;
3:menu_label=8'd165;
endcase
endcase end endfunction
 reg [23:0] background,foreground;reg [7:0] character;reg [5:0] col;
 reg [3:0] fx,fy;reg text_on;reg [10:0] number;reg [3:0] mr;reg neg;
 wire [16:0] contrast100=({7'd0,contrast_q}<<6)+({7'd0,contrast_q}<<5)+({7'd0,contrast_q}<<2);
 integer i;
 always @*begin
  background=technical?legacy_rgb:rgb;foreground=night?24'h90b0b8:24'he8ffff;
  character=32;col=x>>5;fx=x[4:1];fy=y[4:1];text_on=0;number=0;mr=0;neg=0;
  if(!technical)begin
   if(y<96||y>=400)background=night?24'h080e18:24'h123045;
   if(y<32)begin character=phrase(0,col);text_on=1;end
   else if(y<64)begin
    if(col<4)character=phrase(1,col);
    else if(col<9)character=station_name(station,col-4);
    else if(col>=11&&col<15)character=phrase(2,col-11);
    else if(col>=15)character=station==5?phrase(3,col-15):station_name(station+1'b1,col-15);
    text_on=1;
   end else if(y<96)begin
    if(col<4)character=phrase(night?17:16,col);
    text_on=1;
   end
   if(y>=400&&y<416)begin
    for(i=0;i<6;i=i+1)begin
     if(x>=32+i*96&&x<112+i*96)background=i<=station?24'h28a888:(night?24'h18202c:24'h365064);
    end
   end
   if(y>=416&&y<448)begin
    text_on=1;
    case(col)1:character="1";4:character="2";7:character="3";10:character="4";13:character="5";16:character="6";endcase
   end
   if(y>=448)begin text_on=ticker_q;character=phrase(18,{1'b0,ticker_position[9:5]});fx=ticker_position[4:1];end
   if(arrival&&y>=160&&y<224)begin
    background=night?24'h17302a:24'h176044;text_on=y<192;character=phrase(4,col);foreground=24'he8ffd0;
   end
  end
  if(!ready_q)begin
   background=night?24'h080e18:24'h122838;text_on=0;character=32;
   if(y>=128&&y<160)begin text_on=1;
    case(state_q)
     0:character=phrase(7,col);1:character=phrase(8,col);2:character=phrase(9,col);
     3:character=phrase(10,col);4:character=phrase(11,col);default:character=phrase(12,col);
    endcase
   end
   if(y>=192&&y<224)begin text_on=1;
    case(col)2:character="I";3:character="M";4:character="G";6:character=48+count_q;7:character="/";8:character="4";
     11:character="E";12:character="R";13:character="R";
     15:character=error_q[7:4]<10?48+error_q[7:4]:55+error_q[7:4];
     16:character=error_q[3:0]<10?48+error_q[3:0]:55+error_q[3:0];endcase
   end
   if(y>=256&&y<288)begin text_on=1;character=phrase(13,col);end
  end
  if(menu_q)begin
   background=night?24'h080e18:24'h142e42;text_on=0;character=32;
   fx=x[3:0];fy=y[3:0];col=x>>4;
   if(y<16)begin text_on=1;character=phrase(14,col);end
   if(y>=32&&y<416)begin
    mr=(y-32)>>5;fy=(y-32)&15;
    if(mr==item_q)background=night?24'h244438:24'h27684e;
    text_on=y[4]==0;character=menu_label(mr,col);
    case(mr)
     0:begin number=bright_q[8]?-bright_q:bright_q;neg=bright_q[8];end
     1:number=contrast100[16:8];2:number=volume_q;3:number=ticker_q;4:number=wave_q;
     5:number=audio_q;6:number=transition_q;7:number=station+1'b1;8:number=night;9:number=technical;
     10:number=emergency;11:number=0;
    endcase
    if(col==25)character=neg?"-":" ";
    if(col==26)character=48+(number/100)%10;
    if(col==27)character=48+(number/10)%10;
    if(col==28)character=48+number%10;
    if(mr==11&&col>=25)case(col)25:character="A";26:character="U";27:character="T";28:character="O";default:character=32;endcase
   end
   if(y>=448&&y<464)begin text_on=1;character=phrase(15,col);end
  end
  if(emergency)begin
   background=night?24'h501008:24'ha81810;foreground=24'hfff0b0;text_on=0;
   col=x>>5;fx=x[4:1];fy=y[4:1];character=32;
   if(y>=160&&y<192)begin text_on=1;character=phrase(5,col);end
   if(y>=256&&y<288)begin text_on=1;character=phrase(6,col);end
  end
`ifdef SIM_RAW_DISPLAY
  background=rgb;text_on=0;
`endif
 end
 wire [15:0] font_bits;
 wire [7:0] font_index=character-8'd32;
 vehicle_font font(clk,{font_index,fy},font_bits);
 reg [23:0] bg_q,fg_q;reg [3:0] bit_q;reg text_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin out_de<=0;out_x<=0;out_y<=0;bg_q<=0;fg_q<=0;bit_q<=0;text_q<=0;end
  else begin out_de<=de;out_x<=x;out_y<=y;bg_q<=background;fg_q<=foreground;bit_q<=fx;text_q<=text_on;end
 end
 assign out_rgb=text_q&&font_bits[15-bit_q]?fg_q:bg_q;
endmodule
