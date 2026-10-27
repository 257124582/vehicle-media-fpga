`timescale 1ns/1ps
module tb_board_menu;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,key_next_n=1,key_auto_n=1,key_mode_n=1;
 reg signed [8:0] brightness=32;reg [9:0] contrast=384;reg [3:0] volume=8;
 reg ticker_enable=1,wave_enable=1,continuous_test=0,transition=1,command_ready=1;
 wire command_valid;wire [4:0] command;wire signed [15:0] value;
 wire next_press,auto_press,mode_press,menu_active;wire [3:0] menu_item;
 board_menu #(.DEBOUNCE(3),.LONG_CYCLES(24)) dut(clk,rst,key_next_n,key_auto_n,key_mode_n,
  brightness,contrast,volume,ticker_enable,wave_enable,continuous_test,transition,
  command_ready,command_valid,command,value,next_press,auto_press,mode_press,menu_active,menu_item,1'b0,1'b0,1'b0,3'd0,,);
 integer next_count=0,auto_count=0,mode_count=0,accepted=0,selected_mode=3;
 reg [4:0] log_command[0:127];reg signed [15:0] log_value[0:127];
 reg was_stalled=0;reg [4:0] stalled_command;reg signed [15:0] stalled_value;
 always @(posedge clk)if(!rst)begin
  if(next_press)next_count=next_count+1;if(auto_press)auto_count=auto_count+1;
  if(mode_press)mode_count=mode_count+1;
  if(was_stalled&&!command_ready&&(!command_valid||command!==stalled_command||value!==stalled_value))
   $fatal(1,"pending UI command changed while UART had priority");
  was_stalled=command_valid&&!command_ready;stalled_command=command;stalled_value=value;
  if(command_valid&&command_ready)begin
   log_command[accepted]=command;log_value[accepted]=value;accepted=accepted+1;
   case(command)
    4:selected_mode=value;
    6:begin if(selected_mode!=0)$fatal(1,"BRIGHT issued before original image mode");brightness<=value;end
    7:begin if(selected_mode!=0)$fatal(1,"CONTRAST issued before original image mode");contrast<=value;end
    8:volume<=value;
    9:transition<=value;
    14:continuous_test<=value;
    15:ticker_enable<=value;
    16:wave_enable<=value;
   endcase
  end
 end
 task press_next;
  begin @(negedge clk);key_next_n=0;repeat(10)@(negedge clk);key_next_n=1;repeat(10)@(negedge clk);end
 endtask
 task press_auto;
  begin @(negedge clk);key_auto_n=0;repeat(10)@(negedge clk);key_auto_n=1;repeat(10)@(negedge clk);end
 endtask
 task press_mode(input bit long_press);
  begin @(negedge clk);key_mode_n=0;repeat(long_press?36:10)@(negedge clk);
   key_mode_n=1;repeat(10)@(negedge clk);end
 endtask
 task check_command(input integer at,input integer cmd,input integer val);
  begin if(log_command[at]!==cmd||$signed(log_value[at])!=val)
   $fatal(1,"UI command[%d] got cmd=%d value=%d expected cmd=%d value=%d",at,log_command[at],log_value[at],cmd,val);end
 endtask
 task parameter_press(input bit increase,input integer cmd,input integer expected_value,input bit needs_mode);
  integer start;
  begin start=accepted;
   if(increase)press_auto();else press_next();
   if(accepted!=start+(needs_mode?2:1))$fatal(1,"missing/duplicate UI command");
   if(needs_mode)begin check_command(start,4,0);check_command(start+1,cmd,expected_value);end
   else check_command(start,cmd,expected_value);
  end
 endtask
 integer start,i;
 initial begin
  repeat(5)@(negedge clk);rst=0;
  press_next();press_auto();press_mode(0);
  if(next_count!=1||auto_count!=1||mode_count!=1||accepted!=0)
   $fatal(1,"normal playback key behavior changed");
  // Contact bounce must not trigger a mode or menu event.
  for(i=0;i<4;i=i+1)begin key_mode_n=0;@(negedge clk);key_mode_n=1;@(negedge clk);end
  repeat(8)@(negedge clk);
  if(mode_count!=1||menu_active)$fatal(1,"mode contact bounce accepted");
  press_mode(1);
  if(!menu_active||menu_item!=0||mode_count!=1)$fatal(1,"long press also fired short MODE");
  command_ready=0;start=accepted;press_auto();
  if(!command_valid||command!=4||value!=0||accepted!=start)$fatal(1,"UI did not hold pending command for UART arbitration");
  repeat(15)@(negedge clk);command_ready=1;repeat(6)@(negedge clk);
  if(accepted!=start+2)$fatal(1,"two-command transaction was lost");
  check_command(start,4,0);check_command(start+1,6,40);
  brightness=125;parameter_press(1,6,127,1);
  brightness=-126;parameter_press(0,6,-128,1);
  brightness=-120;parameter_press(0,6,-128,1);
  press_mode(0);if(menu_item!=1)$fatal(1,"menu item did not advance");
  contrast=760;parameter_press(1,7,768,1);
  contrast=16;parameter_press(0,7,0,1);
  contrast=736;parameter_press(1,7,768,1);
  press_mode(0);volume=15;parameter_press(1,8,15,0);
  volume=0;parameter_press(0,8,0,0);
  volume=8;parameter_press(1,8,9,0);
  press_mode(0);parameter_press(1,15,0,0);parameter_press(0,15,1,0);
  press_mode(0);parameter_press(1,16,0,0);parameter_press(0,16,1,0);
  press_mode(0);parameter_press(1,14,1,0);parameter_press(0,14,0,0);
  press_mode(0);parameter_press(1,9,0,0);parameter_press(0,9,1,0);
  repeat(6)press_mode(0);if(menu_item!=0)$fatal(1,"menu item did not wrap");
  if(next_count!=1||auto_count!=1||mode_count!=1)$fatal(1,"menu keys leaked into playback actions");
  press_mode(1);if(menu_active||mode_count!=1)$fatal(1,"leaving menu fired short MODE");
  press_mode(0);press_next();press_auto();
  if(mode_count!=2||next_count!=2||auto_count!=2)$fatal(1,"normal keys did not resume");
  $display("TEST PASS board_menu: debounce, short/long separation, UART arbitration, signed clamps, mode-before-parameter and all toggles");
  $finish;
 end
endmodule
