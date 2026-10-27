`timescale 1ns/1ps
// Retry at most three complete media initializations, with a quiet interval.
// Counter is reset only by board reset/manual rescan, never by its own retry.
module media_retry #(parameter DELAY_CYCLES=10000000,MAX_RETRIES=3)(
 input clk,input rst,input manual_rescan,input sd_failed,input [7:0] sd_error,
 output reg retry,output reg [1:0] attempts);
 reg [23:0] delay_count;reg pending;
 always @(posedge clk or posedge rst)begin
  if(rst)begin retry<=0;attempts<=0;delay_count<=0;pending<=0;end
  else begin
   retry<=0;
   if(manual_rescan)begin attempts<=0;delay_count<=0;pending<=0;end
   else if(sd_failed&&sd_error!=0&&attempts<MAX_RETRIES)begin pending<=1;delay_count<=0;end
   else if(pending)begin
    if(delay_count==DELAY_CYCLES-1)begin retry<=1;attempts<=attempts+1'b1;pending<=0;delay_count<=0;end
    else delay_count<=delay_count+1'b1;
   end
  end
 end
endmodule
