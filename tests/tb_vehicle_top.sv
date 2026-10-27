`timescale 1ns/1ps
// Real scene/menu/UART/playback/OSD/audio RTL; media availability is forced.
module tb_vehicle_top;
 reg clk=0;always #10 clk=~clk;reg kn=1,ka=1,km=1,rx=1;
 wire tx,sc,sd,hc,h0,h1,h2,sck,mosi,cs;wire [7:0] seg;wire [5:0] sel;wire [3:0] led;
 vehicle_media_top dut(clk,1'b1,kn,ka,km,1'b1,sck,mosi,cs,rx,tx,sc,sd,hc,h0,h1,h2,seg,sel,led);
 defparam dut.u_menu.DEBOUNCE=3;defparam dut.u_menu.LONG_CYCLES=24;
 wire bv;wire [7:0] bd;wire ub,ut;
 uart_byte decoder(dut.pixel_clk,dut.prst,tx,bv,bd,1'b0,8'd0,ub,ut);
 string line="",last="";integer replies=0,issued=0,alerts=0,px=0,py=0,frames=0,nonzero=0;
 always @(posedge dut.pixel_clk)if(!dut.prst)begin
  if(dut.uart_command_valid)issued=issued+1;
  if(dut.alert_trigger)alerts=alerts+1;
  if(dut.audio_valid&&dut.audio_l!=0)nonzero=nonzero+1;
  if(bv)begin
   if(bd==10)begin last=line;line="";replies=replies+1;end
   else if(bd!=13)line={line,bd};
  end
 end
 always @(negedge dut.pixel_clk)if(!dut.prst&&dut.u_hdmi.I_axis_s_valid)begin
  if(dut.vehicle_x!=px||dut.vehicle_y!=py)$fatal(1,"vehicle pixel alignment");
  if(dut.u_hdmi.I_axis_s_user!=(px==0&&py==0)||dut.u_hdmi.I_axis_s_last!=(px==639))$fatal(1,"axis markers");
  if(dut.emergency&&px==639&&py==300&&dut.u_hdmi.I_axis_s_data!==24'ha81810)$fatal(1,"emergency actual HDMI pixel");
  if(px==639)begin px=0;if(py==479)begin py=0;frames=frames+1;end else py=py+1;end else px=px+1;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.pixel_clk);end endtask
 task send(input string text,input string expected);integer j,b,r;reg [7:0] c;begin
  r=replies;
  for(j=0;j<=text.len();j=j+1)begin
   c=j==text.len()?10:text.getc(j);rx=0;#8680;
   for(b=0;b<8;b=b+1)begin rx=c[b];#8680;end
   rx=1;#8680;
  end
  wait(replies>r);cycles(3);
  if(expected=="S")begin if(last.len()!=50||last.substr(0,1)!="S:")$fatal(1,"bad snapshot %s",last);end
  else if(last!=expected)$fatal(1,"reply for %s got %s",text,last);
 end endtask
 integer r,before_samples;reg [1:0] frozen_image;reg [4:0] frozen_alpha;
 initial begin
  force dut.power_count=20'h80000;force dut.scan_start=0;force dut.count=3'd4;force dut.scan_complete=1'b1;
  force dut.sd_ok=1;force dut.fetch_enable=0;force dut.audio_trigger=0;
  wait(!dut.prst);cycles(20);
  send("VEHICLE","S");if(last.substr(2,3)!="A3")$fatal(1,"A3 schema");
  send("STATUS","S");if(last.substr(2,3)!="A1")$fatal(1,"A1 schema");
  send("DETAIL","S");if(last.substr(2,3)!="A2")$fatal(1,"A2 schema");
  send("NIGHT 1","OK");wait(dut.night_mode);cycles(5);if(dut.brightness!=-48)$fatal(1,"night preset top");
  wait(dut.u_adjust.br_latch==-48&&dut.u_adjust.co_latch==224);
  wait(dut.vehicle_de&&dut.vehicle_x==200&&dut.vehicle_y==250);#1;
  if(dut.vehicle_rgb!==24'h000018)$fatal(1,"night image pixels %h",dut.vehicle_rgb);
  send("NIGHT 0","OK");wait(!dut.night_mode);
  wait(dut.u_adjust.br_latch==0&&dut.u_adjust.co_latch==256);
  wait(dut.vehicle_de&&dut.vehicle_x==200&&dut.vehicle_y==250);#1;
  if(dut.vehicle_rgb!==24'h202040)$fatal(1,"day image pixels %h",dut.vehicle_rgb);
send("STATION 5","OK");wait(dut.station==5);
  send("VEHICLE","S");if(last.substr(6,9)!="05FF")$fatal(1,"terminal next station %s",last);
  send("VIEW 1","OK");wait(dut.technical);send("VIEW 0","OK");wait(!dut.technical);
  send("EMERGENCY","ERR");send("NIGHT 2","ERR");send("VEHICLE 1","ERR");send("STATION 6","ERR");
  before_samples=nonzero;send("EMERGENCY 1","OK");wait(dut.emergency);cycles(10);
  frozen_image=dut.image;frozen_alpha=dut.alpha;
  send("NEXT","ERR");send("AUTO 0","ERR");send("STATION 0","ERR");send("VEHICLE","S");
  if(dut.image!=frozen_image||dut.alpha!=frozen_alpha)$fatal(1,"emergency playback freeze");
  wait(frames>=6);if(nonzero<=before_samples)$fatal(1,"emergency no actual PCM");
  send("VOLUME 0","OK");wait(dut.audio_valid);cycles(2);if(dut.audio_l!=0)$fatal(1,"emergency mute");
  send("EMERGENCY 0","OK");wait(!dut.emergency);
  r=replies;kn=0;cycles(40);kn=1;cycles(12);wait(dut.emergency);
  kn=0;cycles(40);kn=1;cycles(12);wait(!dut.emergency);cycles(10);
  if(replies!=r||issued!=replies||alerts!=2)$fatal(1,"reply/event accounting");
  if(dut.ready_violations||dut.underflows)$fatal(1,"transport counter");
  $display("TEST PASS vehicle top: real UART A1/A2/A3, event replies, station, theme, physical emergency, actual HDMI emergency pixels and PCM/mute; media status and physical interfaces modeled");$finish;
 end
 initial begin #1200000000;$fatal(1,"timeout replies=%d last=%s em=%b",replies,last,dut.emergency);end
endmodule
