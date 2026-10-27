`timescale 1ns/1ps
module tb_console;
 reg clk=0;always #20 clk=~clk;reg rst=1,start=0;reg [7:0] txbyte;wire htx,ctx,busy,rv;wire [7:0] rxbyte;
 uart_byte host(clk,rst,ctx,rv,rxbyte,start,txbyte,busy,htx);
 wire cv,reply,err,rescan;wire [4:0] cmd;wire signed [15:0] value;wire [1:0] image;wire auto_play;wire [5:0] period;
 wire [2:0] mode;wire [7:0] threshold;wire signed [8:0] brightness;wire [9:0] contrast;wire [3:0] volume;
 wire transition,compare,adaptive,audio;wire [4:0] alpha;reg tick=0;integer clocks=0,reply_count=0,audios=0;reg [2047:0] response;
 uart_console console(clk,rst,htx,ctx,cv,cmd,value,reply,err,192'hA1_3C_80_00_00_00_05_80_12345678_ABCDEF00_00000000_00000000,192'hA2_71_00_0F_1A_30_80_05_00000001_02625A00_00000000_0000208D,192'd0);
 playback_control control(clk,rst,tick,3'd4,1'b1,1'b0,1'b0,1'b0,cv,cmd,value,reply,err,rescan,
  image,auto_play,period,mode,threshold,brightness,contrast,volume,transition,compare,adaptive,alpha,audio,,,,1'b0,1'b0);
 always @(posedge clk)begin clocks<=clocks+1;tick<=clocks%1000==0;if(audio)audios=audios+1;
  if(rv)begin response={response[2039:0],rxbyte};if(rxbyte==10)reply_count=reply_count+1;end end
 task raw_line;input string s;integer j;begin
  for(j=0;j<s.len();j=j+1)begin wait(!busy);@(negedge clk);txbyte=s.getc(j);start=1;@(negedge clk);start=0;wait(!busy);end
  wait(!busy);@(negedge clk);txbyte=10;start=1;@(negedge clk);start=0;wait(!busy);
 end endtask
 task line;input string s;integer old;begin old=reply_count;response=0;raw_line(s);wait(reply_count>old);@(negedge clk);end endtask
 integer before_busy;
 initial begin
  repeat(8)@(negedge clk);rst=0;repeat(2000)@(negedge clk);
  line("AUTO 0");if(response!=32'h4f4b0d0a||auto_play)$fatal(1,"AUTO response");
  line("PERIOD 12");if(period!=12)$fatal(1,"period");
  line("MODE 3");if(mode!=3)$fatal(1,"mode");
  line("BRIGHT -128");if(brightness!=-128)$fatal(1,"signed brightness");
  line("CONTRAST 768");if(contrast!=768)$fatal(1,"contrast");
  line("VOLUME 16");if(response!=40'h4552520d0a||volume!=8)$fatal(1,"range rejection");
  line("MODE");if(response!=40'h4552520d0a)$fatal(1,"missing argument");
  line("ABCDEFGHIJKLMNO 1");if(response!=40'h4552520d0a)$fatal(1,"bounded name");
  line("NEXT");repeat(40000)@(negedge clk);if(image!=1||alpha!=16||audios!=2)$fatal(1,"fade/commit/audio %d %d %d",image,alpha,audios);
  line("STATUS");if(response!={"S:A13C80000000058012345678ABCDEF000000000000000000",16'h0d0a})$fatal(1,"snapshot serialization %h",response);
  line("DETAIL");if(response!={"S:A271000F1A3080050000000102625A00000000000000208D",16'h0d0a})$fatal(1,"detail serialization");
  before_busy=reply_count;response=0;raw_line("STATUS");raw_line("MODE 0");
  wait(reply_count>=before_busy+2);@(negedge clk);
  if(response[39:0]!=40'h4552520d0a||mode!=3)$fatal(1,"busy command must return ERR without modifying settings");
  $display("TEST PASS console: physical UART 8N1, numeric/signed parsing, bounds, hex snapshot, 33-frame fade and image/audio commit");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
