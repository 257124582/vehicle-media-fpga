`timescale 1ns/1ps
module tb_media_retry;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,manual_rescan=0,sd_failed=0;reg [7:0] sd_error=0;
 wire retry;wire [1:0] attempts;
 media_retry #(.DELAY_CYCLES(7),.MAX_RETRIES(3)) dut(clk,rst,manual_rescan,sd_failed,sd_error,retry,attempts);
 integer retries=0,cycle=0,last_retry=-1000;
 always @(negedge clk)if(!rst)begin
  cycle=cycle+1;
  if(retry)begin
   if(cycle-last_retry<7)$fatal(1,"retry pulses violated quiet interval");
   retries=retries+1;last_retry=cycle;
  end
 end
 task fault(input [7:0] code);
  begin @(negedge clk);sd_failed=1;sd_error=code;@(negedge clk);sd_failed=0;end
 endtask
 task wait_retry(input integer expected);
  integer watchdog;
  begin
   watchdog=0;
   while(retries<expected&&watchdog<30)begin @(negedge clk);watchdog=watchdog+1;end
   if(retries!=expected)$fatal(1,"missing retry expected=%d observed=%d",expected,retries);
   repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  fault(0);repeat(20)@(negedge clk);
  if(retries!=0||attempts!=0)$fatal(1,"zero error incorrectly retried");
  fault(8'h01);repeat(5)@(negedge clk);
  if(retries!=0)$fatal(1,"retry fired before quiet delay");
  wait_retry(1);if(attempts!=1)$fatal(1,"attempt counter mismatch");
  fault(8'h02);wait_retry(2);
  fault(8'h04);wait_retry(3);
  if(attempts!=3)$fatal(1,"expected bounded three automatic retries");
  fault(8'h01);repeat(40)@(negedge clk);
  if(retries!=3||attempts!=3)$fatal(1,"automatic retry budget restarted itself");
  // Manual rescan restores the retry budget and cancels any pending retry.
  @(negedge clk);manual_rescan=1;@(negedge clk);manual_rescan=0;
  if(attempts!=0)$fatal(1,"manual rescan did not restore budget");
  fault(8'h03);repeat(2)@(negedge clk);
  manual_rescan=1;@(negedge clk);manual_rescan=0;
  repeat(20)@(negedge clk);
  if(retries!=3||attempts!=0)$fatal(1,"manual rescan failed to cancel pending retry");
  fault(8'h01);wait_retry(4);
  rst=1;@(negedge clk);rst=0;repeat(3)@(negedge clk);
  if(attempts!=0||retry)$fatal(1,"board reset failed to restore retry state");
  $display("TEST PASS media_retry: quiet delay, exactly three retries, ignored zero error, manual/reset budget and pending cancellation");
  $finish;
 end
endmodule
