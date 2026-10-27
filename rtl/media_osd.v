`timescale 1ns/1ps
// Zero-latency compositor. Frame snapshots prevent tearing of the menus/ticker.
// CLOCK_HZ is the pixel clock; UP is elapsed operating time, not civil time.
module media_osd #(parameter CLOCK_HZ=25000000)(
 input clk,input rst,input frame_tick,input de,input [10:0] x,input [9:0] y,
 input [23:0] rgb,input [2:0] image_count,input [1:0] image,input [2:0] mode,
 input autoplay,input signed [8:0] brightness,input [9:0] contrast,input [3:0] volume,
 input menu_active,input [2:0] menu_item,input ticker_enable,input wave_enable,
 input continuous_audio,input [15:0] source_width,input [15:0] source_height,
 input [7:0] error_code,input wave_pixel,output reg [23:0] out_rgb,input overlay_enable,input transition_enable,input night_mode);
 reg [24:0] second_counter;
 reg [3:0] sec_ones,sec_tens,min_ones,min_tens,hour_ones,hour_tens;
 reg [23:0] uptime;
 reg [9:0] ticker_phase;
 reg [2:0] count_q,mode_q,item_q;
 reg [1:0] image_q;
 reg autoplay_q,negative_q,menu_q,ticker_q,wave_q,audio_q,transition_q;
 reg [8:0] bright_abs_q;
 reg [9:0] contrast_q;
 reg [3:0] volume_q;
 reg [15:0] width_q,height_q;
 reg [7:0] error_q;
 wire [8:0] brightness_abs=brightness[8]?(~brightness+9'd1):brightness;
 // One shared serial binary-to-BCD engine; no pixel-rate divider or multiplier.
 reg [15:0] numeric_shift;
 reg [19:0] bcd_work,bcd_adjust;
 reg [4:0] numeric_count;
 reg [2:0] numeric_job;
 reg numeric_busy;
 reg [19:0] width_bcd,height_bcd,bright_bcd,contrast_bcd,volume_bcd;
 wire [16:0] contrast_times100=({7'd0,contrast_q}<<6)+({7'd0,contrast_q}<<5)+({7'd0,contrast_q}<<2);
 integer k;
 always @*begin
  bcd_adjust=bcd_work;
  for(k=0;k<5;k=k+1)if(bcd_work[k*4+:4]>=5)bcd_adjust[k*4+:4]=bcd_work[k*4+:4]+4'd3;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   second_counter<=0;sec_ones<=0;sec_tens<=0;min_ones<=0;min_tens<=0;hour_ones<=0;hour_tens<=0;
   uptime<=0;ticker_phase<=0;count_q<=0;image_q<=0;mode_q<=0;item_q<=0;
   autoplay_q<=0;negative_q<=0;menu_q<=0;ticker_q<=1;wave_q<=0;audio_q<=0;transition_q<=1;
   bright_abs_q<=0;contrast_q<=256;volume_q<=8;width_q<=640;height_q<=480;error_q<=0;
   numeric_shift<=0;bcd_work<=0;numeric_count<=0;numeric_job<=0;numeric_busy<=0;
   width_bcd<=20'h00640;height_bcd<=20'h00480;bright_bcd<=0;contrast_bcd<=20'h00100;volume_bcd<=20'h00008;
  end else begin
   if(second_counter==CLOCK_HZ-1)begin
    second_counter<=0;
    if(sec_ones!=9)sec_ones<=sec_ones+1'b1;
    else begin
     sec_ones<=0;
     if(sec_tens!=5)sec_tens<=sec_tens+1'b1;
     else begin
      sec_tens<=0;
      if(min_ones!=9)min_ones<=min_ones+1'b1;
      else begin
       min_ones<=0;
       if(min_tens!=5)min_tens<=min_tens+1'b1;
       else begin
        min_tens<=0;
        if(hour_ones!=9)hour_ones<=hour_ones+1'b1;
        else begin hour_ones<=0;hour_tens<=hour_tens==9?0:hour_tens+1'b1;end
       end
      end
     end
    end
   end else second_counter<=second_counter+1'b1;
   if(frame_tick)begin
    uptime<={hour_tens,hour_ones,min_tens,min_ones,sec_tens,sec_ones};
    count_q<=image_count;image_q<=image;mode_q<=mode;item_q<=menu_item;
    autoplay_q<=autoplay;negative_q<=brightness[8];bright_abs_q<=brightness_abs;
    contrast_q<=contrast;volume_q<=volume;menu_q<=menu_active;ticker_q<=ticker_enable;
    wave_q<=wave_enable;audio_q<=continuous_audio;transition_q<=transition_enable;width_q<=source_width;height_q<=source_height;error_q<=error_code;
    if(ticker_enable)ticker_phase<=ticker_phase+1'b1;
    numeric_shift<=source_width;bcd_work<=0;numeric_count<=16;numeric_job<=0;numeric_busy<=1;
   end else if(numeric_busy)begin
    bcd_work<={bcd_adjust[18:0],numeric_shift[15]};numeric_shift<=numeric_shift<<1;
    numeric_count<=numeric_count-1'b1;
    if(numeric_count==1)begin
     case(numeric_job)
      0:width_bcd<={bcd_adjust[18:0],numeric_shift[15]};
      1:height_bcd<={bcd_adjust[18:0],numeric_shift[15]};
      2:bright_bcd<={bcd_adjust[18:0],numeric_shift[15]};
      3:contrast_bcd<={bcd_adjust[18:0],numeric_shift[15]};
      4:volume_bcd<={bcd_adjust[18:0],numeric_shift[15]};
     endcase
     bcd_work<=0;numeric_count<=16;numeric_job<=numeric_job+1'b1;
     case(numeric_job)
      0:numeric_shift<=height_q;
      1:numeric_shift<={7'd0,bright_abs_q};
      2:numeric_shift<=contrast_times100[16:8];
      3:numeric_shift<={12'd0,volume_q};
      default:numeric_busy<=0;
     endcase
    end
   end
  end
 end

 function [7:0] decimal_char;input [3:0] digit;begin decimal_char=8'd48+digit;end endfunction
 function [7:0] hex_char;input [3:0] digit;begin hex_char=digit<10?8'd48+digit:8'd65+digit-10;end endfunction
 function [7:0] mode_char;input [2:0] md;input [1:0] pos;begin
  case(md)
   0:case(pos)0:mode_char="O";1:mode_char="R";2:mode_char="I";3:mode_char="G";endcase
   1:case(pos)0:mode_char="G";1:mode_char="R";2:mode_char="A";3:mode_char="Y";endcase
   2:case(pos)0:mode_char="T";1:mode_char="H";2:mode_char="R";3:mode_char=" ";endcase
   3:case(pos)0:mode_char="E";1:mode_char="D";2:mode_char="G";3:mode_char="E";endcase
   4:case(pos)0:mode_char="B";1:mode_char="R";2:mode_char="T";3:mode_char=" ";endcase
   5:case(pos)0:mode_char="C";1:mode_char="O";2:mode_char="N";3:mode_char="T";endcase
   default:mode_char="?";
  endcase
 end endfunction
 function [34:0] ascii_font;input [7:0] ch;begin
  case(ch)
   "0":ascii_font=35'b01110_10001_10011_10101_11001_10001_01110;
   "1":ascii_font=35'b00100_01100_00100_00100_00100_00100_01110;
   "2":ascii_font=35'b01110_10001_00001_00010_00100_01000_11111;
   "3":ascii_font=35'b11110_00001_00001_01110_00001_00001_11110;
   "4":ascii_font=35'b00010_00110_01010_10010_11111_00010_00010;
   "5":ascii_font=35'b11111_10000_10000_11110_00001_00001_11110;
   "6":ascii_font=35'b01110_10000_10000_11110_10001_10001_01110;
   "7":ascii_font=35'b11111_00001_00010_00100_01000_01000_01000;
   "8":ascii_font=35'b01110_10001_10001_01110_10001_10001_01110;
   "9":ascii_font=35'b01110_10001_10001_01111_00001_00001_01110;
   "A":ascii_font=35'b01110_10001_10001_11111_10001_10001_10001;
   "B":ascii_font=35'b11110_10001_10001_11110_10001_10001_11110;
   "C":ascii_font=35'b01111_10000_10000_10000_10000_10000_01111;
   "D":ascii_font=35'b11110_10001_10001_10001_10001_10001_11110;
   "E":ascii_font=35'b11111_10000_10000_11110_10000_10000_11111;
   "F":ascii_font=35'b11111_10000_10000_11110_10000_10000_10000;
   "G":ascii_font=35'b01111_10000_10000_10111_10001_10001_01111;
   "H":ascii_font=35'b10001_10001_10001_11111_10001_10001_10001;
   "I":ascii_font=35'b01110_00100_00100_00100_00100_00100_01110;
   "J":ascii_font=35'b00111_00010_00010_00010_00010_10010_01100;
   "K":ascii_font=35'b10001_10010_10100_11000_10100_10010_10001;
   "L":ascii_font=35'b10000_10000_10000_10000_10000_10000_11111;
   "M":ascii_font=35'b10001_11011_10101_10101_10001_10001_10001;
   "N":ascii_font=35'b10001_11001_10101_10011_10001_10001_10001;
   "O":ascii_font=35'b01110_10001_10001_10001_10001_10001_01110;
   "P":ascii_font=35'b11110_10001_10001_11110_10000_10000_10000;
   "Q":ascii_font=35'b01110_10001_10001_10001_10101_10010_01101;
   "R":ascii_font=35'b11110_10001_10001_11110_10100_10010_10001;
   "S":ascii_font=35'b01111_10000_10000_01110_00001_00001_11110;
   "T":ascii_font=35'b11111_00100_00100_00100_00100_00100_00100;
   "U":ascii_font=35'b10001_10001_10001_10001_10001_10001_01110;
   "V":ascii_font=35'b10001_10001_10001_10001_10001_01010_00100;
   "W":ascii_font=35'b10001_10001_10001_10101_10101_10101_01010;
   "X":ascii_font=35'b10001_10001_01010_00100_01010_10001_10001;
   "Y":ascii_font=35'b10001_10001_01010_00100_00100_00100_00100;
   "Z":ascii_font=35'b11111_00001_00010_00100_01000_10000_11111;
   ":":ascii_font=35'b00000_00100_00100_00000_00100_00100_00000;
   "/":ascii_font=35'b00001_00001_00010_00100_01000_10000_10000;
   "+":ascii_font=35'b00000_00100_00100_11111_00100_00100_00000;
   "-":ascii_font=35'b00000_00000_00000_11111_00000_00000_00000;
   "%":ascii_font=35'b11001_11010_00100_00100_01000_10110_00110;
   "?":ascii_font=35'b01110_10001_00001_00010_00100_00000_00100;
   default:ascii_font=0;
  endcase
 end endfunction

 // Finite 16x16 Chinese ticker, binary dot masks. No external font file needed.
 // Text: 国产芯片车载多媒体终端  安全出行文明乘车  实时图像音频展示 
 function [15:0] chinese_row;input [8:0] address;begin
  case(address)
   9'd0:chinese_row=16'h3ffc;
   9'd1:chinese_row=16'h7ffe;
   9'd2:chinese_row=16'h6006;
   9'd3:chinese_row=16'h6ff6;
   9'd4:chinese_row=16'h6186;
   9'd5:chinese_row=16'h6186;
   9'd6:chinese_row=16'h6ff6;
   9'd7:chinese_row=16'h6186;
   9'd8:chinese_row=16'h61e6;
   9'd9:chinese_row=16'h61a6;
   9'd10:chinese_row=16'h6ff6;
   9'd11:chinese_row=16'h6006;
   9'd12:chinese_row=16'h6006;
   9'd13:chinese_row=16'h7ffe;
   9'd14:chinese_row=16'h2004;
   9'd16:chinese_row=16'h0180;
   9'd17:chinese_row=16'h0180;
   9'd18:chinese_row=16'h1ffe;
   9'd19:chinese_row=16'h0410;
   9'd20:chinese_row=16'h0630;
   9'd21:chinese_row=16'h0230;
   9'd22:chinese_row=16'h3ffe;
   9'd23:chinese_row=16'h3000;
   9'd24:chinese_row=16'h3000;
   9'd25:chinese_row=16'h3000;
   9'd26:chinese_row=16'h3000;
   9'd27:chinese_row=16'h2000;
   9'd28:chinese_row=16'h6000;
   9'd29:chinese_row=16'h4000;
   9'd32:chinese_row=16'h0420;
   9'd33:chinese_row=16'h0420;
   9'd34:chinese_row=16'h7ffe;
   9'd35:chinese_row=16'h0420;
   9'd36:chinese_row=16'h0420;
   9'd37:chinese_row=16'h0400;
   9'd38:chinese_row=16'h0180;
   9'd39:chinese_row=16'h34c8;
   9'd40:chinese_row=16'h34cc;
   9'd41:chinese_row=16'h2404;
   9'd42:chinese_row=16'h6406;
   9'd43:chinese_row=16'h6410;
   9'd44:chinese_row=16'h0410;
   9'd45:chinese_row=16'h07f0;
   9'd48:chinese_row=16'h1860;
   9'd49:chinese_row=16'h1860;
   9'd50:chinese_row=16'h1860;
   9'd51:chinese_row=16'h1860;
   9'd52:chinese_row=16'h1ffe;
   9'd53:chinese_row=16'h1ffc;
   9'd54:chinese_row=16'h1800;
   9'd55:chinese_row=16'h1800;
   9'd56:chinese_row=16'h1ff0;
   9'd57:chinese_row=16'h1010;
   9'd58:chinese_row=16'h1010;
   9'd59:chinese_row=16'h3010;
   9'd60:chinese_row=16'h2010;
   9'd61:chinese_row=16'h6010;
   9'd62:chinese_row=16'h0010;
   9'd64:chinese_row=16'h0100;
   9'd65:chinese_row=16'h0300;
   9'd66:chinese_row=16'h3ffc;
   9'd67:chinese_row=16'h3ff8;
   9'd68:chinese_row=16'h0c80;
   9'd69:chinese_row=16'h0880;
   9'd70:chinese_row=16'h3ff8;
   9'd71:chinese_row=16'h3ffc;
   9'd72:chinese_row=16'h0080;
   9'd73:chinese_row=16'h0080;
   9'd74:chinese_row=16'h7ffe;
   9'd75:chinese_row=16'h0180;
   9'd76:chinese_row=16'h0080;
   9'd77:chinese_row=16'h0080;
   9'd78:chinese_row=16'h0080;
   9'd80:chinese_row=16'h0c48;
   9'd81:chinese_row=16'h3f4c;
   9'd82:chinese_row=16'h3f44;
   9'd83:chinese_row=16'h7ffe;
   9'd84:chinese_row=16'h7ffe;
   9'd85:chinese_row=16'h0860;
   9'd86:chinese_row=16'h7f6c;
   9'd87:chinese_row=16'h342c;
   9'd88:chinese_row=16'h2428;
   9'd89:chinese_row=16'h7f38;
   9'd90:chinese_row=16'h0430;
   9'd91:chinese_row=16'h3f30;
   9'd92:chinese_row=16'h7c7a;
   9'd93:chinese_row=16'h05ce;
   9'd94:chinese_row=16'h0404;
   9'd96:chinese_row=16'h0200;
   9'd97:chinese_row=16'h07f0;
   9'd98:chinese_row=16'h0ff8;
   9'd99:chinese_row=16'h3a30;
   9'd100:chinese_row=16'h2260;
   9'd101:chinese_row=16'h03c0;
   9'd102:chinese_row=16'h0740;
   9'd103:chinese_row=16'h3cfe;
   9'd104:chinese_row=16'h038c;
   9'd105:chinese_row=16'h0e8c;
   9'd106:chinese_row=16'h18d8;
   9'd107:chinese_row=16'h0070;
   9'd108:chinese_row=16'h01e0;
   9'd109:chinese_row=16'h3f80;
   9'd110:chinese_row=16'h3800;
   9'd112:chinese_row=16'h1108;
   9'd113:chinese_row=16'h13fe;
   9'd114:chinese_row=16'h13fe;
   9'd115:chinese_row=16'h7d08;
   9'd116:chinese_row=16'h7df8;
   9'd117:chinese_row=16'h2508;
   9'd118:chinese_row=16'h2df8;
   9'd119:chinese_row=16'h6c60;
   9'd120:chinese_row=16'h6ffe;
   9'd121:chinese_row=16'h3bfe;
   9'd122:chinese_row=16'h18f0;
   9'd123:chinese_row=16'h1dac;
   9'd124:chinese_row=16'h2726;
   9'd125:chinese_row=16'h6622;
   9'd126:chinese_row=16'h0020;
   9'd128:chinese_row=16'h1840;
   9'd129:chinese_row=16'h1840;
   9'd130:chinese_row=16'h1040;
   9'd131:chinese_row=16'h37fe;
   9'd132:chinese_row=16'h37fc;
   9'd133:chinese_row=16'h70f0;
   9'd134:chinese_row=16'h71d0;
   9'd135:chinese_row=16'h5158;
   9'd136:chinese_row=16'h134c;
   9'd137:chinese_row=16'h1646;
   9'd138:chinese_row=16'h1dfa;
   9'd139:chinese_row=16'h11f0;
   9'd140:chinese_row=16'h1040;
   9'd141:chinese_row=16'h1040;
   9'd142:chinese_row=16'h0040;
   9'd144:chinese_row=16'h1040;
   9'd145:chinese_row=16'h10c0;
   9'd146:chinese_row=16'h30fc;
   9'd147:chinese_row=16'h2588;
   9'd148:chinese_row=16'h6fd8;
   9'd149:chinese_row=16'h7b70;
   9'd150:chinese_row=16'h5870;
   9'd151:chinese_row=16'h10f8;
   9'd152:chinese_row=16'h238e;
   9'd153:chinese_row=16'h7e70;
   9'd154:chinese_row=16'h6018;
   9'd155:chinese_row=16'h0080;
   9'd156:chinese_row=16'h7cf0;
   9'd157:chinese_row=16'h6018;
   9'd160:chinese_row=16'h1020;
   9'd161:chinese_row=16'h1126;
   9'd162:chinese_row=16'h1126;
   9'd163:chinese_row=16'h7dfe;
   9'd164:chinese_row=16'h7c00;
   9'd165:chinese_row=16'h0dfe;
   9'd166:chinese_row=16'h6dfe;
   9'd167:chinese_row=16'h6820;
   9'd168:chinese_row=16'h29fe;
   9'd169:chinese_row=16'h2952;
   9'd170:chinese_row=16'h1d52;
   9'd171:chinese_row=16'h7d52;
   9'd172:chinese_row=16'h6152;
   9'd173:chinese_row=16'h0106;
   9'd174:chinese_row=16'h0004;
   9'd208:chinese_row=16'h0100;
   9'd209:chinese_row=16'h0180;
   9'd210:chinese_row=16'h3ffc;
   9'd211:chinese_row=16'h300c;
   9'd212:chinese_row=16'h330c;
   9'd213:chinese_row=16'h0200;
   9'd214:chinese_row=16'h0600;
   9'd215:chinese_row=16'h7ffe;
   9'd216:chinese_row=16'h0c30;
   9'd217:chinese_row=16'h0c20;
   9'd218:chinese_row=16'h07c0;
   9'd219:chinese_row=16'h01f0;
   9'd220:chinese_row=16'h073c;
   9'd221:chinese_row=16'h3c0e;
   9'd222:chinese_row=16'h2000;
   9'd224:chinese_row=16'h0180;
   9'd225:chinese_row=16'h0380;
   9'd226:chinese_row=16'h02c0;
   9'd227:chinese_row=16'h0660;
   9'd228:chinese_row=16'h1c38;
   9'd229:chinese_row=16'h781e;
   9'd230:chinese_row=16'h6ff6;
   9'd231:chinese_row=16'h0180;
   9'd232:chinese_row=16'h0180;
   9'd233:chinese_row=16'h1ff8;
   9'd234:chinese_row=16'h0180;
   9'd235:chinese_row=16'h0180;
   9'd236:chinese_row=16'h0180;
   9'd237:chinese_row=16'h3ffc;
   9'd240:chinese_row=16'h0180;
   9'd241:chinese_row=16'h0180;
   9'd242:chinese_row=16'h318c;
   9'd243:chinese_row=16'h318c;
   9'd244:chinese_row=16'h318c;
   9'd245:chinese_row=16'h3ffc;
   9'd246:chinese_row=16'h3ff8;
   9'd247:chinese_row=16'h0180;
   9'd248:chinese_row=16'h2184;
   9'd249:chinese_row=16'h2184;
   9'd250:chinese_row=16'h2184;
   9'd251:chinese_row=16'h2184;
   9'd252:chinese_row=16'h3ffc;
   9'd253:chinese_row=16'h3ffc;
   9'd254:chinese_row=16'h0004;
   9'd256:chinese_row=16'h1800;
   9'd257:chinese_row=16'h11fe;
   9'd258:chinese_row=16'h3000;
   9'd259:chinese_row=16'h6000;
   9'd260:chinese_row=16'h4800;
   9'd261:chinese_row=16'h1bfe;
   9'd262:chinese_row=16'h31fe;
   9'd263:chinese_row=16'h3018;
   9'd264:chinese_row=16'h7018;
   9'd265:chinese_row=16'h5018;
   9'd266:chinese_row=16'h1018;
   9'd267:chinese_row=16'h1018;
   9'd268:chinese_row=16'h1018;
   9'd269:chinese_row=16'h1078;
   9'd270:chinese_row=16'h1030;
   9'd272:chinese_row=16'h0300;
   9'd273:chinese_row=16'h0100;
   9'd274:chinese_row=16'h0180;
   9'd275:chinese_row=16'h7ffe;
   9'd276:chinese_row=16'h7ffe;
   9'd277:chinese_row=16'h0820;
   9'd278:chinese_row=16'h0c20;
   9'd279:chinese_row=16'h0460;
   9'd280:chinese_row=16'h0640;
   9'd281:chinese_row=16'h02c0;
   9'd282:chinese_row=16'h0380;
   9'd283:chinese_row=16'h03c0;
   9'd284:chinese_row=16'h0e70;
   9'd285:chinese_row=16'h781e;
   9'd286:chinese_row=16'h2000;
   9'd288:chinese_row=16'h007c;
   9'd289:chinese_row=16'h7efe;
   9'd290:chinese_row=16'h66c6;
   9'd291:chinese_row=16'h66c6;
   9'd292:chinese_row=16'h66fe;
   9'd293:chinese_row=16'h7ec6;
   9'd294:chinese_row=16'h66c6;
   9'd295:chinese_row=16'h66c6;
   9'd296:chinese_row=16'h66fe;
   9'd297:chinese_row=16'h7e86;
   9'd298:chinese_row=16'h6686;
   9'd299:chinese_row=16'h6186;
   9'd300:chinese_row=16'h0184;
   9'd301:chinese_row=16'h031c;
   9'd304:chinese_row=16'h0078;
   9'd305:chinese_row=16'h3ff0;
   9'd306:chinese_row=16'h0180;
   9'd307:chinese_row=16'h7ffe;
   9'd308:chinese_row=16'h01a0;
   9'd309:chinese_row=16'h0da4;
   9'd310:chinese_row=16'h7dbc;
   9'd311:chinese_row=16'h0db0;
   9'd312:chinese_row=16'h3db6;
   9'd313:chinese_row=16'h6ffc;
   9'd314:chinese_row=16'h07e0;
   9'd315:chinese_row=16'h1db8;
   9'd316:chinese_row=16'h318e;
   9'd317:chinese_row=16'h6180;
   9'd318:chinese_row=16'h0100;
   9'd320:chinese_row=16'h0100;
   9'd321:chinese_row=16'h0300;
   9'd322:chinese_row=16'h3ffc;
   9'd323:chinese_row=16'h3ff8;
   9'd324:chinese_row=16'h0c80;
   9'd325:chinese_row=16'h0880;
   9'd326:chinese_row=16'h3ff8;
   9'd327:chinese_row=16'h3ffc;
   9'd328:chinese_row=16'h0080;
   9'd329:chinese_row=16'h0080;
   9'd330:chinese_row=16'h7ffe;
   9'd331:chinese_row=16'h0180;
   9'd332:chinese_row=16'h0080;
   9'd333:chinese_row=16'h0080;
   9'd334:chinese_row=16'h0080;
   9'd368:chinese_row=16'h0100;
   9'd369:chinese_row=16'h0180;
   9'd370:chinese_row=16'h3ffe;
   9'd371:chinese_row=16'h2006;
   9'd372:chinese_row=16'h2444;
   9'd373:chinese_row=16'h0640;
   9'd374:chinese_row=16'h1340;
   9'd375:chinese_row=16'h1840;
   9'd376:chinese_row=16'h0cc0;
   9'd377:chinese_row=16'h7ffe;
   9'd378:chinese_row=16'h0180;
   9'd379:chinese_row=16'h01e0;
   9'd380:chinese_row=16'h0738;
   9'd381:chinese_row=16'h3c0e;
   9'd382:chinese_row=16'h2004;
   9'd384:chinese_row=16'h000c;
   9'd385:chinese_row=16'h3c0c;
   9'd386:chinese_row=16'h7c0c;
   9'd387:chinese_row=16'h65fe;
   9'd388:chinese_row=16'h65fe;
   9'd389:chinese_row=16'h7c0c;
   9'd390:chinese_row=16'h7c8c;
   9'd391:chinese_row=16'h64cc;
   9'd392:chinese_row=16'h644c;
   9'd393:chinese_row=16'h644c;
   9'd394:chinese_row=16'h7c0c;
   9'd395:chinese_row=16'h640c;
   9'd396:chinese_row=16'h600c;
   9'd397:chinese_row=16'h0038;
   9'd400:chinese_row=16'h3ffc;
   9'd401:chinese_row=16'h7ffe;
   9'd402:chinese_row=16'h6306;
   9'd403:chinese_row=16'h63e6;
   9'd404:chinese_row=16'h6666;
   9'd405:chinese_row=16'h6fc6;
   9'd406:chinese_row=16'h61c6;
   9'd407:chinese_row=16'h6f76;
   9'd408:chinese_row=16'h6d96;
   9'd409:chinese_row=16'h60c6;
   9'd410:chinese_row=16'h6386;
   9'd411:chinese_row=16'h61c6;
   9'd412:chinese_row=16'h7ffe;
   9'd413:chinese_row=16'h7ffe;
   9'd414:chinese_row=16'h2004;
   9'd416:chinese_row=16'h1980;
   9'd417:chinese_row=16'h19f0;
   9'd418:chinese_row=16'h13f0;
   9'd419:chinese_row=16'h37fc;
   9'd420:chinese_row=16'h37fc;
   9'd421:chinese_row=16'h7264;
   9'd422:chinese_row=16'h73fc;
   9'd423:chinese_row=16'h11cc;
   9'd424:chinese_row=16'h16f8;
   9'd425:chinese_row=16'h11b8;
   9'd426:chinese_row=16'h1768;
   9'd427:chinese_row=16'h15a4;
   9'd428:chinese_row=16'h1722;
   9'd429:chinese_row=16'h3060;
   9'd430:chinese_row=16'h0040;
   9'd432:chinese_row=16'h0100;
   9'd433:chinese_row=16'h0180;
   9'd434:chinese_row=16'h3ffc;
   9'd435:chinese_row=16'h0c30;
   9'd436:chinese_row=16'h0420;
   9'd437:chinese_row=16'h7ffe;
   9'd438:chinese_row=16'h7ffe;
   9'd440:chinese_row=16'h1ff8;
   9'd441:chinese_row=16'h1818;
   9'd442:chinese_row=16'h1ff8;
   9'd443:chinese_row=16'h1818;
   9'd444:chinese_row=16'h1818;
   9'd445:chinese_row=16'h1ff8;
   9'd446:chinese_row=16'h1000;
   9'd448:chinese_row=16'h0800;
   9'd449:chinese_row=16'h28fe;
   9'd450:chinese_row=16'h2f30;
   9'd451:chinese_row=16'h2c30;
   9'd452:chinese_row=16'h28fe;
   9'd453:chinese_row=16'h7fc6;
   9'd454:chinese_row=16'h08d6;
   9'd455:chinese_row=16'h28d6;
   9'd456:chinese_row=16'h2bd6;
   9'd457:chinese_row=16'h6ed6;
   9'd458:chinese_row=16'h0ef6;
   9'd459:chinese_row=16'h0c30;
   9'd460:chinese_row=16'h386c;
   9'd461:chinese_row=16'h61c6;
   9'd464:chinese_row=16'h3ff8;
   9'd465:chinese_row=16'h3ffc;
   9'd466:chinese_row=16'h300c;
   9'd467:chinese_row=16'h3ffc;
   9'd468:chinese_row=16'h3320;
   9'd469:chinese_row=16'h3ff8;
   9'd470:chinese_row=16'h3ff8;
   9'd471:chinese_row=16'h3320;
   9'd472:chinese_row=16'h3ffe;
   9'd473:chinese_row=16'h26c8;
   9'd474:chinese_row=16'h2658;
   9'd475:chinese_row=16'h2670;
   9'd476:chinese_row=16'h67b8;
   9'd477:chinese_row=16'h471e;
   9'd481:chinese_row=16'h1ff8;
   9'd485:chinese_row=16'h7ffe;
   9'd486:chinese_row=16'h3ffe;
   9'd487:chinese_row=16'h0180;
   9'd488:chinese_row=16'h0990;
   9'd489:chinese_row=16'h1998;
   9'd490:chinese_row=16'h118c;
   9'd491:chinese_row=16'h318c;
   9'd492:chinese_row=16'h6186;
   9'd493:chinese_row=16'h0380;
   9'd494:chinese_row=16'h0300;
   default:chinese_row=0;
  endcase
 end endfunction

 reg [7:0] character;
 reg [5:0] character_index;
 reg [3:0] text_column,text_row,panel_row;
 reg [34:0] glyph;
 reg text_area,text_dot,panel_selected;
 reg [23:0] foreground,layer;
 wire [10:0] ticker_position={1'b0,x[9:0]}+{1'b0,ticker_phase};
 wire [15:0] ticker_bits=chinese_row({ticker_position[9:5],y[3:0]});
 wire ticker_dot=ticker_position[4:0]>=8&&ticker_position[4:0]<24&&ticker_bits[23-ticker_position[4:0]];
 function [23:0] shade;input [23:0] background;begin
  shade={1'b0,background[23:17],1'b0,background[15:9],1'b0,background[7:1]};
 end endfunction
 always @*begin
  character=" ";character_index=0;text_column=0;text_row=0;panel_row=0;text_area=0;
  foreground=24'hc0ffff;panel_selected=0;layer=rgb;
  // Wave pixels are derived from the actual PCM, then covered by higher HUD layers.
  if(wave_q&&x>=16&&x<624&&y>=320&&y<432)begin
   layer=shade(rgb);
   if(wave_pixel)layer=24'h40ffb0;
  end
  if(y<48)layer=shade(rgb);
  if(y>=64&&y<208&&x>=416)begin
   panel_row=(y-64)>>4;
   panel_selected=menu_q&&panel_row==item_q&&panel_row<7;
   layer=shade(rgb);
   if(panel_selected)layer={1'b0,rgb[23:17],2'b00,rgb[15:10],2'b00,rgb[7:2]}+24'h002020;
   if(panel_selected&&x<420)layer=24'h40ffb0;
  end
  if(ticker_q&&y>=440)layer=shade(rgb);
  if(error_q!=0&&y>=46&&y<48)layer=24'hff6040;
  if(x>=8&&x<632&&y>=8&&y<22)begin
   text_area=1;character_index=(x-8)>>4;text_column=((x-8)&15)>>1;text_row=(y-8)>>1;
   case(character_index)
    0:character="A";1:character="N";2:character="L";3:character="O";4:character="G";5:character="I";6:character="C";
    8:character="V";9:character="E";10:character="H";11:character="I";12:character="C";13:character="L";14:character="E";
    16:character="M";17:character="E";18:character="D";19:character="I";20:character="A";
    27:character="U";28:character="P";
    30:character=decimal_char(uptime[23:20]);31:character=decimal_char(uptime[19:16]);32:character=":";
    33:character=decimal_char(uptime[15:12]);34:character=decimal_char(uptime[11:8]);35:character=":";
    36:character=decimal_char(uptime[7:4]);37:character=decimal_char(uptime[3:0]);
   endcase
  end else if(x>=8&&x<632&&y>=28&&y<42)begin
   text_area=1;character_index=(x-8)>>4;text_column=((x-8)&15)>>1;text_row=(y-28)>>1;
   case(character_index)
    0:character="I";1:character="M";2:character="G";4:character=count_q==0?"-":decimal_char({2'd0,image_q}+4'd1);
    5:character="/";6:character=decimal_char({1'b0,count_q});
    8:character="A";9:character="U";10:character="T";11:character="O";13:character="O";
    14:character=autoplay_q?"N":"F";15:character=autoplay_q?" ":"F";
    17:character="M";18:character="O";19:character="D";20:character="E";
    22,23,24,25:character=mode_char(mode_q,character_index-22);
    27:character="E";28:character="R";29:character="R";31:character=hex_char(error_q[7:4]);32:character=hex_char(error_q[3:0]);
   endcase
  end else if(x>=420&&x<640&&y>=65&&y<208)begin
   text_area=1;character_index=(x-420)>>4;text_column=((x-420)&15)>>1;text_row=((y-65)&15)>>1;panel_row=(y-65)>>4;
   if(text_row>=7)text_area=0;
   case(panel_row)
    0:case(character_index)
     0:character="B";1:character="R";2:character="I";3:character="G";4:character="H";5:character="T";
     7:character=negative_q?"-":"+";8:character=decimal_char(bright_bcd[11:8]);9:character=decimal_char(bright_bcd[7:4]);10:character=decimal_char(bright_bcd[3:0]);
    endcase
    1:case(character_index)
     0:character="C";1:character="O";2:character="N";3:character="T";4:character="R";5:character="A";6:character="S";7:character="T";
     9:character=decimal_char(contrast_bcd[11:8]);10:character=decimal_char(contrast_bcd[7:4]);11:character=decimal_char(contrast_bcd[3:0]);12:character="%";
    endcase
    2:case(character_index)
     0:character="V";1:character="O";2:character="L";3:character="U";4:character="M";5:character="E";
     7:character=decimal_char(volume_bcd[7:4]);8:character=decimal_char(volume_bcd[3:0]);
    endcase
    3:case(character_index)
     0:character="T";1:character="I";2:character="C";3:character="K";4:character="E";5:character="R";
     7:character="O";8:character=ticker_q?"N":"F";9:character=ticker_q?" ":"F";
    endcase
    4:case(character_index)
     0:character="W";1:character="A";2:character="V";3:character="E";5:character="O";6:character=wave_q?"N":"F";7:character=wave_q?" ":"F";
    endcase
    5:case(character_index)
     0:character="A";1:character="U";2:character="D";3:character="I";4:character="O";
     6:character=audio_q?"T":"B";7:character=audio_q?"O":"E";8:character=audio_q?"N":"E";9:character=audio_q?"E":"P";
    endcase
    6:case(character_index)
     0:character="T";1:character="R";2:character="A";3:character="N";4:character="S";5:character="I";6:character="T";7:character="I";8:character="O";9:character="N";
     11:character="O";12:character=transition_q?"N":"F";13:character=transition_q?" ":"F";
    endcase
    7:case(character_index)
     0:character="S";1:character="R";2:character="C";
     4:character=decimal_char(width_bcd[15:12]);5:character=decimal_char(width_bcd[11:8]);6:character=decimal_char(width_bcd[7:4]);7:character=decimal_char(width_bcd[3:0]);8:character="X";
     9:character=decimal_char(height_bcd[15:12]);10:character=decimal_char(height_bcd[11:8]);11:character=decimal_char(height_bcd[7:4]);12:character=decimal_char(height_bcd[3:0]);
    endcase
    8:case(character_index)
     0:character="M";1:character="E";2:character="N";3:character="U";
     5:character=menu_q?"S":"P";6:character=menu_q?"E":"L";7:character=menu_q?"T":"A";8:character=menu_q?" ":"Y";
     9:character=menu_q?decimal_char({1'b0,item_q}+4'd1):" ";
    endcase
   endcase
   if(panel_selected)foreground=24'hffffff;
  end else if(wave_q&&x>=24&&x<344&&y>=321&&y<335)begin
   text_area=1;character_index=(x-24)>>4;text_column=((x-24)&15)>>1;text_row=(y-321)>>1;
   case(character_index)
    0:character="R";1:character="E";2:character="A";3:character="L";
    5:character="P";6:character="C";7:character="M";
    9:character="4";10:character="8";11:character="K";12:character="H";13:character="Z";
   endcase
  end
  glyph=ascii_font(character);
  text_dot=text_area&&text_column<5&&text_row<7?glyph[34-text_row*5-text_column]:0;
  if(night_mode===1'b1)foreground={1'b0,foreground[23:17],1'b0,foreground[15:9],1'b0,foreground[7:1]};
  if(text_dot)layer=foreground;
  if(ticker_q&&y>=448&&y<464&&ticker_dot)layer=24'hfff080;
  out_rgb=(de&&overlay_enable)?layer:rgb;
 end
endmodule
