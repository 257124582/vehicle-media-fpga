`timescale 1ns/1ps
module tb_system;
 reg refclk=0;always #10 refclk=~refclk;wire utx;reg urx=1;wire [7:0] seg;wire [5:0] sel;wire [3:0] led;wire scl,sda,vc,v0,v1,v2,sck,mosi,cs;
 vehicle_media_top dut(refclk,1'b1,1'b1,1'b1,1'b1,1'b1,sck,mosi,cs,urx,utx,scl,sda,vc,v0,v1,v2,seg,sel,led);
 reg [23:0] gold0[0:307199],gold1[0:307199],gold2[0:307199],gold3[0:307199];
 integer clock_count=0,prior_line=-1,prior_frame=-1,px=0,py=0,checked=0,slot=0,completed=0,k;reg checking=0;reg [23:0] expected;
 reg [3:0] verified=0;reg [31:0] checksums[0:3];
 always @(posedge dut.pixel_clk)begin
  clock_count=clock_count+1;
  if(dut.reload_wait)checking=0;
  if(dut.u_hdmi.I_axis_s_valid)begin
   if(dut.u_hdmi.I_axis_s_user)begin
    if(prior_frame>=0&&clock_count-prior_frame!=420000)$fatal(1,"frame period");
    prior_frame=clock_count;px=0;py=0;slot=dut.image;checking=dut.scan_complete&&!dut.reload_wait&&dut.alpha==16&&dut.mode==0&&!dut.transition;
   end
   if(px==0)begin if(prior_line>=0&&py!=0&&clock_count-prior_line!=800)$fatal(1,"line period");prior_line=clock_count;end
   if(dut.u_hdmi.I_axis_s_last!=(px==639))$fatal(1,"line length at %d,%d",px,py);
   if(checking)begin
    case(slot)0:expected=gold0[py*640+px];1:expected=gold1[py*640+px];2:expected=gold2[py*640+px];3:expected=gold3[py*640+px];endcase
    if(dut.u_hdmi.I_axis_s_data!==expected)$fatal(1,"integrated pixel slot %d %d,%d got=%h expected=%h",slot,px,py,dut.u_hdmi.I_axis_s_data,expected);
    checked=checked+1;
   end
   if(px==639)begin px=0;if(py==479)begin if(checking)begin verified[slot]=1;completed=completed+1;end py=0;end else py=py+1;end
   else px=px+1;
  end else if(px!=0)$fatal(1,"gap within active line");
 end
 task send;input string text;integer j,b;reg [7:0] byte_value;begin
  for(j=0;j<=text.len();j=j+1)begin byte_value=j==text.len()?10:text.getc(j);
   urx=0;#8680;for(b=0;b<8;b=b+1)begin urx=byte_value[b];#8680;end urx=1;#8680;
  end
  #1000000;
 end endtask
 initial begin
  force dut.overlay_enable=0;
  $readmemh("assets/reference/01_DAY.hex",gold0);$readmemh("assets/reference/02_NIGHT.hex",gold1);
  $readmemh("assets/reference/03_WARN.hex",gold2);$readmemh("assets/reference/04_PARK.hex",gold3);
  for(k=0;k<4;k=k+1)begin checksums[k]=0;end
  for(k=0;k<307200;k=k+1)begin checksums[0]+=gold0[k];checksums[1]+=gold1[k];checksums[2]+=gold2[k];checksums[3]+=gold3[k];end
  wait(dut.scan_complete&&dut.count==4);
  $display("SYSTEM initial four images loaded");
  for(k=0;k<4;k=k+1)if(dut.writes[k]!==checksums[k])$fatal(1,"load checksum slot %d",k);
  send("AUTO 0");send("TRANSITION 0");
  for(k=0;k<4;k=k+1)begin wait(verified[k]);send("NEXT");end
  if(dut.underflows!=0||dut.cache_error!=0||dut.sd_error!=0||dut.ready_violations!=0)$fatal(1,"end-to-end fault");
  if(dut.read_verified!=15)$fatal(1,"SDRAM integrity flags");
  $display("SYSTEM initial playback passed, starting RESCAN");
  send("RESCAN");wait(dut.reload_wait);wait(!dut.scan_complete);wait(dut.scan_complete&&!dut.reload_wait);
  for(k=0;k<4;k=k+1)if(dut.writes[k]!==checksums[k])$fatal(1,"reload checksum");
  verified=0;wait(verified[0]);
  if(dut.underflows!=0||dut.cache_error!=0)$fatal(1,"rescan caused FIFO faults");
  $display("TEST PASS SYSTEM: 4 fragmented files to actual cache/CDC/control/image/color RTL, 40/25MHz domains, UART NEXT and RESCAN, all slots plus reload frame, %d checked pixels, zero underflows; OSD/wave bypassed for raw matching and separately tested; HDMI/SDRAM/SD physical layers modeled",checked);$finish;
 end
 initial begin #(64'd4000000000);$fatal(1,"integration timeout count=%d state=%d verified=%h underflows=%d",dut.count,dut.debug_state,verified,dut.underflows);end
endmodule
