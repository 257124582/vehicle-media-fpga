`timescale 1ns/1ps
module uart_byte #(parameter CLK_HZ=25000000,BAUD=115200)(input clk,input rst,input rx,
 output reg rx_valid,output reg [7:0] rx_data,input tx_start,input [7:0] tx_data,output tx_busy,output tx);
 localparam BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
 (* async_reg="true" *)reg [1:0] rx_sync;
 reg [3:0] rx_state,tx_bit;reg [15:0] rx_ticks,tx_ticks;reg [7:0] rx_shift;
 reg [9:0] tx_shift;reg sending;
 assign tx_busy=sending;assign tx=sending?tx_shift[0]:1'b1;
 always @(posedge clk or posedge rst)begin
  if(rst)begin rx_sync<=3;rx_state<=0;rx_ticks<=0;rx_shift<=0;rx_data<=0;rx_valid<=0;
   tx_ticks<=0;tx_bit<=0;tx_shift<=10'h3ff;sending<=0;end
  else begin
   rx_sync<={rx_sync[0],rx};rx_valid<=0;
   case(rx_state)
    0:if(!rx_sync[1])begin rx_state<=1;rx_ticks<=BIT_CYCLES/2-1;end
    1:if(rx_ticks==0)begin if(!rx_sync[1])begin rx_state<=2;rx_ticks<=BIT_CYCLES-1;end else rx_state<=0;end else rx_ticks<=rx_ticks-1'b1;
    2,3,4,5,6,7,8,9:if(rx_ticks==0)begin rx_shift[rx_state-2]<=rx_sync[1];rx_state<=rx_state+1'b1;rx_ticks<=BIT_CYCLES-1;end else rx_ticks<=rx_ticks-1'b1;
    10:if(rx_ticks==0)begin rx_state<=0;if(rx_sync[1])begin rx_valid<=1;rx_data<=rx_shift;end end else rx_ticks<=rx_ticks-1'b1;
    default:rx_state<=0;
   endcase
   if(!sending)begin if(tx_start)begin sending<=1;tx_shift<={1'b1,tx_data,1'b0};tx_bit<=0;tx_ticks<=BIT_CYCLES-1;end end
   else if(tx_ticks==0)begin tx_ticks<=BIT_CYCLES-1;tx_shift<={1'b1,tx_shift[9:1]};
    if(tx_bit==9)sending<=0;else tx_bit<=tx_bit+1'b1;
   end else tx_ticks<=tx_ticks-1'b1;
  end
 end
endmodule

module uart_console(input clk,input rst,input rx,output tx,
 output reg command_valid,output reg [4:0] command,output reg signed [15:0] value,
 input reply_valid,input reply_error,input [191:0] status,input [191:0] detail,input [191:0] vehicle_status);
 wire rx_valid;wire [7:0] rx_data;reg tx_start;reg [7:0] tx_data;wire tx_busy;
 uart_byte u_uart(clk,rst,rx,rx_valid,rx_data,tx_start,tx_data,tx_busy,tx);
 reg [95:0] name;reg [4:0] name_length;reg arg,negative,bad,has_number;reg [15:0] number;
 reg responding,status_reply,error_reply,busy_error;reg [6:0] position;reg [191:0] snapshot;
 function [4:0] decode;input [95:0] s;begin
  case(s)"STATUS":decode=0;"NEXT":decode=1;"AUTO":decode=2;"PERIOD":decode=3;"MODE":decode=4;
   "THRESH":decode=5;"BRIGHT":decode=6;"CONTRAST":decode=7;"VOLUME":decode=8;
   "TRANSITION":decode=9;"COMPARE":decode=10;"ADAPTIVE":decode=11;"RESCAN":decode=12;"DETAIL":decode=13;
   "TESTAUDIO":decode=14;"TICKER":decode=15;"WAVE":decode=16;"EMERGENCY":decode=17;"NIGHT":decode=18;"STATION":decode=19;"VIEW":decode=20;"VEHICLE":decode=21;default:decode=31;endcase
 end endfunction
 function [7:0] hexchar;input [3:0] v;begin hexchar=v<10?8'd48+v:8'd65+v-10;end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin name<=0;name_length<=0;arg<=0;negative<=0;bad<=0;has_number<=0;number<=0;
   command_valid<=0;command<=0;value<=0;tx_start<=0;tx_data<=255;responding<=0;status_reply<=0;
   error_reply<=0;busy_error<=0;position<=0;snapshot<=0;end
  else begin
   command_valid<=0;tx_start<=0;
   if(rx_valid)begin
    if(rx_data==13||rx_data==10)begin
     if(name_length!=0&&responding)busy_error<=1;
     if(name_length!=0&&!responding)begin
      command<=bad||(decode(name)==21&&has_number)||(((decode(name)>1&&decode(name)<12)||(decode(name)>=14&&decode(name)<=20))&&!has_number)?31:decode(name);
      value<=negative?-$signed(number):$signed(number);command_valid<=1;
     end
     name<=0;name_length<=0;arg<=0;negative<=0;bad<=0;has_number<=0;number<=0;
    end else if(rx_data==32)begin if(name_length!=0)arg<=1;end
    else if(!arg)begin
     if(name_length<12)begin name<={name[87:0],rx_data>=97&&rx_data<=122?rx_data-8'd32:rx_data};name_length<=name_length+1'b1;end else bad<=1;
    end else if(rx_data==45&&!has_number&&!negative)negative<=1;
    else if(rx_data>=48&&rx_data<=57)begin
     if(number>999)bad<=1;else number<=number*10+rx_data-48;has_number<=1;
    end else bad<=1;
   end
   if(!responding&&busy_error&&!tx_busy&&!tx_start)begin responding<=1;status_reply<=0;error_reply<=1;position<=0;busy_error<=0;end
   if(reply_valid&&!responding)begin responding<=1;status_reply<=(command==0||command==13||command==21)&&!reply_error;
    error_reply<=reply_error;position<=0;snapshot<=command==21?vehicle_status:(command==13?detail:status);end
   if(responding&&!tx_busy&&!tx_start)begin
    tx_start<=1;
    if(status_reply)begin
     // Fixed hexadecimal record: S:<48 hex digits>\r\n (schema in README).
     if(position==0)tx_data<=83;else if(position==1)tx_data<=58;
     else if(position<50)tx_data<=hexchar(snapshot>>(4*(49-position)));
     else if(position==50)tx_data<=13;else tx_data<=10;
     if(position==51)responding<=0;else position<=position+1'b1;
    end else if(error_reply)begin
     case(position)0:tx_data<=69;1:tx_data<=82;2:tx_data<=82;3:tx_data<=13;default:tx_data<=10;endcase
     if(position==4)responding<=0;else position<=position+1'b1;
    end else begin
     case(position)0:tx_data<=79;1:tx_data<=75;2:tx_data<=13;default:tx_data<=10;endcase
     if(position==3)responding<=0;else position<=position+1'b1;
    end
   end
  end
 end
endmodule
