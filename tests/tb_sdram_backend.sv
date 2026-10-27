`timescale 1ns/1ps
module tb_sdram_backend;
 reg clk=0;always #12.5 clk=~clk;
 wire shifted_clk=~clk;
 reg rst=1,we=0,re=0;reg [20:0] wa=0,ra=0;reg [31:0] wd=0;
 wire initialized,refreshing,busy,rv;wire [31:0] rd;
 sdram_backend dut(clk,shifted_clk,rst,initialized,refreshing,busy,we,wa,wd,4'b0,re,ra,rv,rd);
 integer group_index,j,base,received=0,errors=0,refresh_count=0;reg checking=0;
 time last_refresh=0;
 always @(posedge dut.sclk)if(initialized&&{dut.u_memory.ras_n,dut.u_memory.cas_n,dut.u_memory.we_n}===3'b001)begin
  if(last_refresh!=0&&($time-last_refresh)<70)$fatal(1,"AUTO REFRESH tRC below 70 ns");
  if(refresh_count<8)$display("AUTO_REFRESH t=%0t interval=%0t",$time,$time-last_refresh);
  last_refresh=$time;refresh_count=refresh_count+1;
 end
 function automatic [31:0] pattern(input integer address);
  pattern={((address*137+32'h246831)^((address&255)<<12))&24'hffffff,8'h00};
 endfunction
 always @(posedge clk) if(checking&&rv)begin
  if(rd!==pattern(base+received))begin
   if(errors<16)$display("SDRAM mismatch address=%0d got=%08h expected=%08h",base+received,rd,pattern(base+received));
   errors=errors+1;
  end
  received=received+1;
 end
 task write_words(input integer first,input integer count);
  for(group_index=0;group_index<count;group_index=group_index+4)begin
   wait(initialized&&!refreshing&&!busy);
   for(j=0;j<4;j=j+1)begin
    @(negedge clk);we=1;wa=first+group_index+j;wd=pattern(first+group_index+j);
   end
   @(negedge clk);we=0;
   repeat(20)@(negedge clk);
  end
 endtask
 task read_words(input integer first,input integer count);
  integer n;
  wait(initialized&&!refreshing&&!busy);
  base=first;received=0;checking=1;
  for(n=0;n<count;n=n+1)begin @(negedge clk);re=1;ra=first+n;end
  @(negedge clk);re=0;
  wait(received==count);checking=0;
  repeat(20)@(negedge clk);
 endtask
 initial begin
  #200;rst=0;wait(initialized);repeat(20)@(negedge clk);
  for(integer slot=0;slot<4;slot=slot+1)begin
   write_words(slot*307200,512);write_words((slot+1)*307200-512,512);
  end
  $display("Stored words: %08h %08h %08h %08h",dut.u_memory.model.Bank0[0],dut.u_memory.model.Bank0[1],dut.u_memory.model.Bank0[2],dut.u_memory.model.Bank0[3]);
  if(dut.u_memory.model.Bank0[0]!==pattern(0)||dut.u_memory.model.Bank0[3]!==pattern(3))
   $fatal(1,"SDRAM write placement differs from the requested addresses");
  for(integer slot=0;slot<4;slot=slot+1)begin
   for(integer b=0;b<4;b=b+1)read_words(slot*307200+b*128,128);
   for(integer b=0;b<4;b=b+1)read_words((slot+1)*307200-512+b*128,128);
  end
  #50000;$display("Refresh commands after init: %0d",refresh_count);
  if(refresh_count<16)$fatal(1,"Periodic SDRAM refresh is missing");
  if(errors)$fatal(1,"SDRAM actual vendor core/model: %0d mismatches",errors);
  $display("TEST PASS SDRAM_BACKEND: actual vendor controller plus APUG011 SDRAM bus model, 4096 words across all four frame heads/tails and all banks, periodic refresh with legal tRC, aligned spaced writes and 128-word reads at 40MHz/180deg");
  $finish;
 end
 initial begin #20000000;$fatal(1,"SDRAM timeout");end
endmodule
