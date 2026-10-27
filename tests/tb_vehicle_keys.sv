`timescale 1ns/1ps
module tb_vehicle_keys;
 reg clk=0;always #5 clk=~clk;reg rst=1,kn=1,ka=1,km=1,em=0;
 wire cv,np,ap,mp,menu,et,nt;wire [4:0] cmd;wire signed [15:0] val;wire [3:0] item;
 board_menu #(.DEBOUNCE(3),.LONG_CYCLES(24)) dut(clk,rst,kn,ka,km,9'sd0,10'd256,4'd8,1'b1,1'b1,1'b0,1'b1,1'b1,cv,cmd,val,np,ap,mp,menu,item,em,1'b0,1'b0,3'd2,et,nt);
 integer shorts=0,alerts=0,nights=0,commands=0;reg [4:0] lastcmd;reg signed [15:0] lastval;
 always @(posedge clk)if(!rst)begin
  if(np||ap||mp)shorts=shorts+1;if(et)alerts=alerts+1;if(nt)nights=nights+1;
  if(cv)begin commands=commands+1;lastcmd=cmd;lastval=val;end
 end
 task press(input integer key,input integer cycles);begin
  @(negedge clk);case(key)0:kn=0;1:ka=0;2:km=0;endcase
  repeat(cycles)@(negedge clk);
  case(key)0:kn=1;1:ka=1;2:km=1;endcase
  repeat(10)@(negedge clk);
 end endtask
 integer i;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  press(0,40);press(1,40);
  if(alerts!=1||nights!=1||shorts!=0)$fatal(1,"long leaked short");
  press(0,10);press(1,10);press(2,10);if(shorts!=3)$fatal(1,"short missing");
  press(2,40);if(!menu)$fatal(1,"menu entry");
  for(i=0;i<7;i=i+1)press(2,10);
  if(item!=7)$fatal(1,"new items");
  press(1,10);if(lastcmd!=19||lastval!=3)$fatal(1,"station increment");
  press(2,10);press(1,40);if(lastcmd!=18||lastval!=1||nights!=1)$fatal(1,"menu long night");
  press(2,10);press(1,10);if(lastcmd!=20)$fatal(1,"view");
  press(2,10);press(1,10);if(lastcmd!=17)$fatal(1,"emergency item");
  press(2,10);i=commands;press(0,10);if(commands!=i)$fatal(1,"rescan decrement executed");
  press(1,10);if(lastcmd!=12)$fatal(1,"rescan execute");
  em=1;repeat(4)@(negedge clk);if(menu)$fatal(1,"emergency menu not closed");
  press(0,40);if(alerts!=2||shorts!=3)$fatal(1,"emergency escape");
  $display("TEST PASS vehicle keys: long/short exclusivity, twelve items, menu context, emergency escape");$finish;
 end
endmodule
