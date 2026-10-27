`timescale 1ns/1ps
module playback_control #(parameter CLK_HZ=25000000)(input clk,input rst,input frame_tick,
 input [2:0] image_count,input scan_complete,input next_key,input auto_key,input mode_key,
 input command_valid,input [4:0] command,input signed [15:0] value,
 output reg reply_valid,output reg reply_error,output reg rescan,
 output reg [1:0] image,output reg autoplay,output reg [5:0] period,
 output reg [2:0] mode,output reg [7:0] threshold,output reg signed [8:0] brightness,
 output reg [9:0] contrast,output reg [3:0] volume,output reg transition,output reg compare,output reg adaptive,
 output reg [4:0] alpha,output reg audio_trigger,
 output reg continuous_test,output reg ticker_enable,output reg wave_enable,
 input hold_playback,input night_mode);
 wire held=hold_playback===1'b1;
 wire night_on=night_mode===1'b1;
 reg night_previous;reg signed [8:0] day_bright,night_bright;reg [9:0] day_contrast,night_contrast;
 // commands: STATUS=0,NEXT=1,AUTO=2,PERIOD=3,MODE=4,THRESH=5,BRIGHT=6,
 // CONTRAST=7,VOLUME=8,TRANSITION=9,COMPARE=10,ADAPTIVE=11,RESCAN=12,invalid=31.
 reg [24:0] second_counter;reg [5:0] seconds;reg pending;reg [1:0] fading;
 reg started;reg next_request;
 always @*next_request=!held&&(next_key||(command_valid&&command==1));
 always @(posedge clk or posedge rst)begin
  if(rst)begin night_previous<=0;day_bright<=0;night_bright<=-48;day_contrast<=256;night_contrast<=224;image<=0;autoplay<=1;period<=5;mode<=0;threshold<=128;brightness<=0;contrast<=256;volume<=8;
   continuous_test<=0;ticker_enable<=1;wave_enable<=1;
   transition<=1;compare<=0;adaptive<=0;alpha<=16;audio_trigger<=0;second_counter<=0;seconds<=0;
   pending<=0;fading<=0;started<=0;reply_valid<=0;reply_error<=0;rescan<=0;end
  else begin
   audio_trigger<=0;reply_valid<=0;reply_error<=0;rescan<=0;
   if(auto_key&&!held)begin autoplay<=~autoplay;seconds<=0;end
   if(mode_key&&!held)mode<=mode==5?0:mode+1'b1;
   if(next_request)begin pending<=1;seconds<=0;end
   if(!held&&(!scan_complete||image_count==0))begin started<=0;seconds<=0;alpha<=16;fading<=0;pending<=0;image<=0;end
   if(!held)begin
   if(second_counter==CLK_HZ-1)begin
    second_counter<=0;
    if(started&&autoplay&&fading==0)begin
     if(seconds>=period-1'b1)begin seconds<=0;pending<=1;end else seconds<=seconds+1'b1;
    end
   end else second_counter<=second_counter+1'b1;
   end
   if(frame_tick&&!held&&scan_complete&&image_count!=0)begin
    if(!started)begin started<=1;image<=0;audio_trigger<=1;end
    else case(fading)
     0:if(pending&&image_count>1)begin pending<=0;
       if(transition)begin fading<=1;alpha<=15;end
       else begin image<=image+1>=image_count?0:image+1'b1;audio_trigger<=1;end
      end
     1:if(alpha==0)begin image<=image+1>=image_count?0:image+1'b1;audio_trigger<=1;fading<=2;end
       else alpha<=alpha-1'b1;
     2:if(alpha==15)begin alpha<=16;fading<=0;end else alpha<=alpha+1'b1;
     default:fading<=0;
    endcase
   end
   if(night_on!=night_previous)begin
    night_previous<=night_on;brightness<=night_on?night_bright:day_bright;contrast<=night_on?night_contrast:day_contrast;
   end
   if(command_valid)begin
    reply_valid<=1;
    if(held&&command!=0&&command!=8&&command!=13)reply_error<=1;
    else case(command)
     0,1,13:begin end
     2:if(value==0||value==1)begin autoplay<=value[0];seconds<=0;end else reply_error<=1;
     3:if(value>=1&&value<=60)begin period<=value[5:0];seconds<=0;end else reply_error<=1;
     4:if(value>=0&&value<=5)mode<=value[2:0];else reply_error<=1;
     5:if(value>=0&&value<=255)threshold<=value[7:0];else reply_error<=1;
     6:if(value>=-128&&value<=127)begin brightness<=value[8:0];if(night_on)night_bright<=value[8:0];else day_bright<=value[8:0];end else reply_error<=1;
     7:if(value>=0&&value<=768)begin contrast<=value[9:0];if(night_on)night_contrast<=value[9:0];else day_contrast<=value[9:0];end else reply_error<=1;
     8:if(value>=0&&value<=15)volume<=value[3:0];else reply_error<=1;
     9:if(value==0||value==1)transition<=value[0];else reply_error<=1;
     10:if(value==0||value==1)compare<=value[0];else reply_error<=1;
     11:if(value==0||value==1)adaptive<=value[0];else reply_error<=1;
     12:begin rescan<=1;started<=0;end
     14:if(value==0||value==1)continuous_test<=value[0];else reply_error<=1;
     15:if(value==0||value==1)ticker_enable<=value[0];else reply_error<=1;
     16:if(value==0||value==1)wave_enable<=value[0];else reply_error<=1;
     default:reply_error<=1;
    endcase
   end
  end
 end
endmodule
