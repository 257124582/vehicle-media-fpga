`timescale 1ns/1ps
// Integration scope: actual board/menu/UART/control/color/OSD/audio RTL and
// 40/25 MHz domains. Loaded-media status is forced, fetch is disabled, and
// SD/SDRAM/HDMI physical transports use system_models.v. No TF/Flash claim.
module tb_extensions_system;
 reg refclk=0;always #10 refclk=~refclk;
 reg key1=1,key2=1,key3=1,urx=1;
 wire utx,scl,sda,vc,v0,v1,v2,sck,mosi,cs;
 wire [7:0] seg;wire [5:0] sel;wire [3:0] led;
 vehicle_media_top dut(refclk,1'b1,key1,key2,key3,1'b1,sck,mosi,cs,urx,utx,scl,sda,vc,v0,v1,v2,seg,sel,led);
 defparam dut.u_menu.DEBOUNCE=3;
 defparam dut.u_menu.LONG_CYCLES=20;
 wire reply_byte_valid;wire [7:0] reply_byte;wire unused_busy,unused_tx;
 uart_byte u_reply(dut.pixel_clk,dut.prst,utx,reply_byte_valid,reply_byte,1'b0,8'd0,unused_busy,unused_tx);
 string reply_line="";
 integer ok_count=0,error_count=0,status_count=0,uart_count=0,reply_count=0;
 integer clock_count=0,prior_sof=-1,prior_line=-1,px=0,py=0,frames=0,display_pixels=0;
 integer last_audio=-1,audio_samples=0,nonzero_samples=0,wave_samples=0;
 reg collision_seen=0;
 always @(posedge dut.pixel_clk)begin
  if(!dut.prst)begin
   if(dut.uart_command_valid)uart_count=uart_count+1;
   if(dut.reply_valid)reply_count=reply_count+1;
   if(dut.uart_command_valid&&dut.ui_command_valid)collision_seen=1;
   if(reply_byte_valid)begin
    if(reply_byte==10)begin
     if(reply_line=="OK")ok_count=ok_count+1;
     else if(reply_line=="ERR")error_count=error_count+1;
     else if(reply_line.len()==50&&reply_line.substr(0,1)=="S:")status_count=status_count+1;
     else $fatal(1,"unexpected UART reply %s",reply_line);
     reply_line="";
    end else if(reply_byte!=13)reply_line={reply_line,reply_byte};
   end
  end
 end
 always @(negedge dut.pixel_clk)begin
  clock_count=clock_count+1;
  if(!dut.prst)begin
   if(dut.audio_valid)begin
    if(last_audio>=0&&clock_count-last_audio!=520&&clock_count-last_audio!=521)$fatal(1,"PCM sample period changed");
    last_audio=clock_count;audio_samples=audio_samples+1;
    if(dut.audio_l!==dut.audio_r)$fatal(1,"audio stereo channels differ");
    if(dut.audio_l!=0)nonzero_samples=nonzero_samples+1;
   end
   if(dut.u_hdmi.I_axis_s_valid)begin
    if(dut.u_hdmi.I_axis_s_user)begin
     if(prior_sof>=0&&clock_count-prior_sof!=420000)$fatal(1,"HDMI frame period changed");
     prior_sof=clock_count;
     if(px!=0||py!=0)$fatal(1,"HDMI SOF misaligned");
    end
    if(dut.vehicle_x!=px||dut.vehicle_y!=py)$fatal(1,"HDMI metadata mismatch expected %d,%d got %d,%d",px,py,dut.final_x,dut.final_y);
    if(dut.u_hdmi.I_axis_s_user!=(px==0&&py==0))$fatal(1,"HDMI SOF flag");
    if(dut.u_hdmi.I_axis_s_last!=(px==639))$fatal(1,"HDMI line length");
    if(px==0)begin
     if(prior_line>=0&&py!=0&&clock_count-prior_line!=800)$fatal(1,"HDMI line period changed");
     prior_line=clock_count;
    end
    display_pixels=display_pixels+1;
    if(dut.wave_pixel&&dut.u_osd.wave_q&&dut.final_x>=64&&dut.final_x<576&&dut.final_y>=350&&dut.final_y<426)begin
     if(dut.osd_rgb!==24'h40ffb0)$fatal(1,"PCM wave/raster alignment failed");
     wave_samples=wave_samples+1;
    end
    if(px==639)begin px=0;if(py==479)begin py=0;frames=frames+1;end else py=py+1;end
    else px=px+1;
   end else if(px!=0)$fatal(1,"gap within HDMI active line");
  end
 end
 task cycles;input integer n;begin repeat(n)@(negedge dut.pixel_clk);end endtask
 task long_mode;begin key3=0;cycles(35);key3=1;cycles(12);end endtask
 task short_mode;begin key3=0;cycles(9);key3=1;cycles(12);end endtask
 task increase;begin key2=0;cycles(12);key2=1;cycles(12);end endtask
 task decrease;begin key1=0;cycles(10);key1=1;cycles(12);end endtask
 task serial_bits;input string text;integer j,b;reg [7:0] byte_value;begin
  for(j=0;j<=text.len();j=j+1)begin
   byte_value=j==text.len()?10:text.getc(j);urx=0;#8680;
   for(b=0;b<8;b=b+1)begin urx=byte_value[b];#8680;end
   urx=1;#8680;
  end
 end endtask
 task serial_command;input string text;integer before_replies;begin
  before_replies=ok_count+error_count+status_count;
  serial_bits(text);wait(ok_count+error_count+status_count>before_replies);cycles(5);
 end endtask
 integer before_menu,before_audio,expected_replies;
 initial begin
  force dut.power_count=20'h80000;
  force dut.scan_start=0;
  force dut.count=3'd4;
  force dut.scan_complete=1'b1;
  force dut.source_display=32'h04000300;
  force dut.fetch_enable=1'b0;
  // Continuous-audio test excludes the initial half-second image cue.
  force dut.audio_trigger=1'b0;
  wait(!dut.prst);cycles(20);
  serial_command("AUTO 0");serial_command("TRANSITION 0");serial_command("MODE 0");serial_command("VOLUME 8");
  before_menu=ok_count;long_mode();
  if(!dut.menu_active||dut.menu_item!=0||dut.mode!=0)$fatal(1,"long MODE did not enter settings cleanly");
  increase();if(dut.brightness!=8||dut.mode!=0)$fatal(1,"physical brightness change failed");
  wait(dut.u_adjust.br_latch==8);
  wait(dut.final_de&&dut.final_x==200&&dut.final_y==250);@(negedge dut.pixel_clk);
  if(dut.osd_rgb!==24'h282848)$fatal(1,"physical key did not change actual picture RGB %h",dut.osd_rgb);
  if(ok_count!=before_menu||error_count!=0)$fatal(1,"menu generated unsolicited UART reply");
  // A real UART newline overlaps the board menu's two-command transaction.
  expected_replies=ok_count+1;
  fork
   serial_bits("BRIGHT 32");
   begin
    wait(dut.u_console.u_uart.rx_state==10&&dut.u_console.u_uart.rx_shift==10&&dut.u_console.u_uart.rx_ticks==15);
    key2=0;cycles(12);key2=1;cycles(12);
   end
  join
  wait(ok_count==expected_replies);cycles(10);
  if(!collision_seen||dut.brightness!=16)$fatal(1,"UART/UI arbitration lost queued physical adjustment collision=%b bright=%d",collision_seen,dut.brightness);
  before_menu=ok_count;
  short_mode();if(dut.menu_item!=1)$fatal(1,"menu selection contrast");
  increase();if(dut.contrast!=288)$fatal(1,"physical contrast change failed");
  short_mode();if(dut.menu_item!=2)$fatal(1,"menu selection volume");
  decrease();if(dut.volume!=7)$fatal(1,"physical volume change failed");
  short_mode();increase();if(dut.ticker_enable!=0)$fatal(1,"physical ticker toggle failed");
  short_mode();increase();if(dut.wave_enable!=0)$fatal(1,"physical waveform toggle failed");
  short_mode();increase();if(dut.continuous_test!=1)$fatal(1,"physical continuous-audio toggle failed");
  short_mode();increase();if(dut.transition!=1)$fatal(1,"physical transition toggle failed");
  if(ok_count!=before_menu)$fatal(1,"toggle menu generated UART replies");
  wait(dut.osd_frame_tick);cycles(100);
  if(dut.u_osd.width_bcd!=20'h01024||dut.u_osd.height_bcd!=20'h00768||dut.u_osd.ticker_q||dut.u_osd.wave_q||!dut.u_osd.audio_q||!dut.u_osd.transition_q)
   $fatal(1,"OSD did not reflect integrated source size and physical toggles");
  before_audio=nonzero_samples;wait(nonzero_samples>before_audio+20);
  serial_command("TICKER 1");serial_command("WAVE 1");serial_command("CONTRAST 256");
  wait(dut.u_visual.display_valid);wait(wave_samples>20);
  serial_command("VOLUME 0");wait(dut.audio_valid);cycles(2);
  if(dut.audio_l!=0||dut.audio_r!=0)$fatal(1,"mute did not reach actual HDMI PCM");
  serial_command("VOLUME 8");wait(dut.audio_l!=0);
  serial_command("TESTAUDIO 0");wait(dut.audio_valid);cycles(2);
  if(dut.audio_l!=0)$fatal(1,"continuous test did not stop");
  serial_command("DETAIL");if(status_count!=1)$fatal(1,"UART DETAIL response broken");
  long_mode();if(dut.menu_active)$fatal(1,"long MODE did not exit settings");
  short_mode();if(dut.mode!=1)$fatal(1,"normal short MODE did not change filter");
  wait(frames>=2);cycles(10);
  if(error_count!=0||reply_count!=uart_count||ok_count+status_count!=uart_count)$fatal(1,"UART reply accounting mismatch cmd=%d control=%d serial=%d",uart_count,reply_count,ok_count+status_count);
  if(dut.ready_violations!=0||dut.underflows!=0||audio_samples<100||wave_samples==0)$fatal(1,"integrated timing/audio fault");
  $display("TEST PASS extensions_system: physical short/long keys, seven settings, live RGB brightness, real UART/UI collision without unsolicited replies, source-size OSD, actual PCM/mute/wave aligned with HDMI raster; %d frames %d video pixels %d PCM samples; loaded status forced and physical transports modeled",frames,display_pixels,audio_samples);
  $finish;
 end
 initial begin #150000000;$fatal(1,"extension integration timeout menu=%d item=%d br=%d frames=%d replies=%d wave=%d",dut.menu_active,dut.menu_item,dut.brightness,frames,ok_count,wave_samples);end
endmodule
