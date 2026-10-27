`timescale 1ns/1ps
// Debounced key event. A long event suppresses the release short event.
module vehicle_key #(parameter DEBOUNCE=500000,LONG_CYCLES=20000000)(
 input clk,rst,key_n,output reg short_press,long_press);
 (* async_reg="true" *) reg [1:0] sync;
 reg stable,sent;reg [23:0] bounce;reg [24:0] held;
 always @(posedge clk or posedge rst)begin
  if(rst)begin sync<=3;stable<=1;sent<=0;bounce<=0;held<=0;short_press<=0;long_press<=0;end
  else begin
   sync<={sync[0],key_n};short_press<=0;long_press<=0;
   if(sync[1]==stable)bounce<=0;
   else if(bounce==DEBOUNCE-1)begin
    bounce<=0;stable<=sync[1];
    if(!sync[1])begin held<=0;sent<=0;end
    else if(!sent)short_press<=1;
   end else bounce<=bounce+1'b1;
   if(!stable&&!sent&&sync[1]==0)begin
    if(held==LONG_CYCLES-1)begin sent<=1;long_press<=1;end else held<=held+1'b1;
   end
  end
 end
endmodule
module board_menu #(parameter DEBOUNCE=500000,LONG_CYCLES=20000000)(
 input clk,rst,key_next_n,key_auto_n,key_mode_n,
 input signed [8:0] brightness,input [9:0] contrast,input [3:0] volume,
 input ticker_enable,wave_enable,continuous_test,transition,command_ready,
 output reg command_valid,output reg [4:0] command,output reg signed [15:0] value,
 output next_press,auto_press,mode_press,output reg menu_active,output reg [3:0] menu_item,
 input emergency,night_mode,technical,input [2:0] station,
 output emergency_toggle,night_toggle);
 wire kp_next,kp_auto,kp_mode,lp_next,lp_auto,lp_mode;
 wire held=emergency===1'b1;
 vehicle_key #(.DEBOUNCE(DEBOUNCE),.LONG_CYCLES(LONG_CYCLES)) kn(clk,rst,key_next_n,kp_next,lp_next);
 vehicle_key #(.DEBOUNCE(DEBOUNCE),.LONG_CYCLES(LONG_CYCLES)) ka(clk,rst,key_auto_n,kp_auto,lp_auto);
 vehicle_key #(.DEBOUNCE(DEBOUNCE),.LONG_CYCLES(LONG_CYCLES)) km(clk,rst,key_mode_n,kp_mode,lp_mode);
 assign next_press=kp_next&&!menu_active&&!held;
 assign auto_press=kp_auto&&!menu_active&&!held;
 assign mode_press=kp_mode&&!menu_active&&!held;
 assign emergency_toggle=lp_next&&(!menu_active||held);
 assign night_toggle=lp_auto&&!menu_active&&!held;
 reg parameter_pending;reg [4:0] parameter_command;reg signed [15:0] parameter_value;
 always @(posedge clk or posedge rst)begin
  if(rst)begin menu_active<=0;menu_item<=0;command_valid<=0;command<=0;value<=0;
   parameter_pending<=0;parameter_command<=0;parameter_value<=0;
  end else begin
   if(command_valid&&command_ready)begin
    if(parameter_pending)begin command<=parameter_command;value<=parameter_value;parameter_pending<=0;end
    else command_valid<=0;
   end
   if(held)begin menu_active<=0;end
   else begin
    if(lp_mode)menu_active<=~menu_active;
    if(kp_mode&&menu_active)menu_item<=menu_item==11?0:menu_item+1'b1;
   end
   // In menus a long NEXT/AUTO is one adjustment, never a hidden scene shortcut.
   if(menu_active&&!held&&(kp_next||kp_auto||lp_next||lp_auto)&&!command_valid)begin
    command_valid<=1;
    case(menu_item)
     0:begin command<=4;value<=0;parameter_pending<=1;parameter_command<=6;
      parameter_value<=(kp_auto||lp_auto)?(brightness>119?127:brightness+8):(brightness< -120?-128:brightness-8);end
     1:begin command<=4;value<=0;parameter_pending<=1;parameter_command<=7;
      parameter_value<=(kp_auto||lp_auto)?(contrast>736?768:contrast+32):(contrast<32?0:contrast-32);end
     2:begin command<=8;value<=(kp_auto||lp_auto)?(volume==15?15:volume+1):(volume==0?0:volume-1);end
     3:begin command<=15;value<=!ticker_enable;end
     4:begin command<=16;value<=!wave_enable;end
     5:begin command<=14;value<=!continuous_test;end
     6:begin command<=9;value<=!transition;end
     7:begin command<=19;value<=(kp_auto||lp_auto)?(station==5?5:station+1):(station==0?0:station-1);end
     8:begin command<=18;value<=!night_mode;end
     9:begin command<=20;value<=!technical;end
     10:begin command<=17;value<=!emergency;end
     11:begin if(kp_auto||lp_auto)begin command<=12;value<=0;end else command_valid<=0;end
     default:begin command<=0;value<=0;end
    endcase
   end
  end
 end
endmodule
