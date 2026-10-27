`timescale 1ns/1ps
module vehicle_scene #(parameter CLOCK_HZ=25000000)(
 input clk,rst,frame_tick,input emergency_toggle,night_toggle,
 input command_valid,input [4:0] command,input signed [15:0] value,
 output reg reply_valid,reply_error,output reg emergency,night,technical,
 output reg [2:0] station,output reg arrival,output reg alert_trigger,arrival_trigger,
 output hold_playback,output reg [31:0] emergency_count,recovery_count,response_cycles);
 reg emergency_target,night_target,technical_target;reg [2:0] station_target;
 reg [31:0] arrival_left,latency;reg measuring;
 assign hold_playback=emergency||emergency_target;
 always @(posedge clk or posedge rst)begin
  if(rst)begin emergency<=0;night<=0;technical<=0;station<=0;arrival<=0;
   emergency_target<=0;night_target<=0;technical_target<=0;station_target<=0;
   reply_valid<=0;reply_error<=0;alert_trigger<=0;arrival_trigger<=0;
   emergency_count<=0;recovery_count<=0;response_cycles<=0;arrival_left<=0;latency<=0;measuring<=0;
  end else begin
   reply_valid<=0;reply_error<=0;alert_trigger<=0;arrival_trigger<=0;
   if(measuring)latency<=latency+1'b1;
   if(arrival_left!=0)arrival_left<=arrival_left-1'b1;
   if(command_valid)begin
    reply_valid<=1;
    case(command)
     17:if(value==0||value==1)begin
      emergency_target<=value[0];
      if(value[0]&&!emergency_target)begin latency<=0;measuring<=1;end
     end else reply_error<=1;
     18:if(value==0||value==1)night_target<=value[0];else reply_error<=1;
     19:if(value>=0&&value<=5&&!hold_playback)station_target<=value[2:0];else reply_error<=1;
     20:if((value==0||value==1)&&!hold_playback)technical_target<=value[0];else reply_error<=1;
     21:begin end
     default:reply_error<=1;
    endcase
   end
   // Physical safety event is independent of, and takes precedence over, UART traffic.
   if(emergency_toggle)begin emergency_target<=~emergency_target;
    if(!emergency_target)begin latency<=0;measuring<=1;end
   end
   if(night_toggle)night_target<=~night_target;
   if(frame_tick)begin
    emergency<=emergency_target;night<=night_target;technical<=technical_target;
    if(emergency_target&&!emergency)begin
     emergency_count<=emergency_count+1'b1;alert_trigger<=1;
     response_cycles<=latency;measuring<=0;arrival<=0;arrival_left<=0;
    end else if(!emergency_target&&emergency)recovery_count<=recovery_count+1'b1;
    if(emergency_target)begin arrival<=0;arrival_left<=0;station<=station_target;end
    else if(!emergency&&station!=station_target)begin
     station<=station_target;arrival<=1;arrival_left<=CLOCK_HZ*3;arrival_trigger<=1;
    end else if(arrival_left==0)arrival<=0;
   end
  end
 end
endmodule
