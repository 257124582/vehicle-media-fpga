`timescale 1ns/1ps
module tb_osd;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,frame_tick=0,de=1,overlay_enable=1;
 reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=24'h80c040;
 reg [2:0] image_count=4,mode=0,menu_item=0;
 reg [1:0] image=2;reg autoplay=1;
 reg signed [8:0] brightness=-64;reg [9:0] contrast=384;
 reg [3:0] volume=15;reg menu_active=1,ticker_enable=1,wave_enable=1,continuous_audio=1,transition_enable=1;
 reg [15:0] source_width=1024,source_height=768;
 reg [7:0] error_code=0;reg wave_pixel=0;
 wire [23:0] out_rgb;
 reg [23:0] ticker_reference[0:639];
 integer xx,yy,pixels,fh;reg [9:0] saved_phase;
 media_osd #(.CLOCK_HZ(256)) dut(
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.de(de),.x(x),.y(y),.rgb(rgb),
  .image_count(image_count),.image(image),.mode(mode),.autoplay(autoplay),
  .brightness(brightness),.contrast(contrast),.volume(volume),.menu_active(menu_active),.menu_item(menu_item),
  .ticker_enable(ticker_enable),.wave_enable(wave_enable),.continuous_audio(continuous_audio),
  .source_width(source_width),.source_height(source_height),.error_code(error_code),.wave_pixel(wave_pixel),
  .out_rgb(out_rgb),.overlay_enable(overlay_enable),.transition_enable(transition_enable));
 task frame;begin
  @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(90)@(negedge clk);
 end endtask
 task pixel;input [10:0] px;input [9:0] py;input [23:0] expected;begin
  x=px;y=py;#1;if(out_rgb!==expected)$fatal(1,"OSD pixel %d,%d got %h expected %h",px,py,out_rgb,expected);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;frame();
  if(dut.width_bcd!==20'h01024||dut.height_bcd!==20'h00768||dut.bright_bcd!==20'h00064||dut.contrast_bcd!==20'h00150||dut.volume_bcd!==20'h00015)
   $fatal(1,"shared numeric formatter failed w=%h h=%h b=%h c=%h v=%h",dut.width_bcd,dut.height_bcd,dut.bright_bcd,dut.contrast_bcd,dut.volume_bcd);
  if(!dut.negative_q)$fatal(1,"brightness sign missing");
  pixel(630,5,24'h406020); // half-alpha header retains source information
  pixel(8,8,24'h406020);pixel(10,8,24'hc0ffff); // actual A top-row dot
  pixel(200,250,rgb); // no overlay in photograph interior
  wave_pixel=1;pixel(100,380,24'h40ffb0);pixel(10,8,24'hc0ffff);wave_pixel=0;
  pixel(417,70,24'h40ffb0); // selected menu edge
  overlay_enable=0;pixel(10,8,rgb);pixel(417,70,rgb);overlay_enable=1;
  de=0;pixel(10,8,rgb);de=1;
  brightness=127;source_width=321;source_height=241;volume=0;
  repeat(5)@(negedge clk);
  if(dut.bright_bcd!=20'h00064||!dut.negative_q)$fatal(1,"mid-frame status changed");
  frame();
  if(dut.width_bcd!=20'h00321||dut.height_bcd!=20'h00241||dut.bright_bcd!=20'h00127||dut.negative_q||dut.volume_bcd!=0)
   $fatal(1,"next-frame parameter snapshot failed");
  // Verify smooth scrolling using actual rendered glyph pixels, not the phase register alone.
  x=0;y=451;for(xx=0;xx<640;xx=xx+1)begin x=xx;#1;ticker_reference[xx]=out_rgb;end
  frame();
  for(xx=0;xx<639;xx=xx+1)begin x=xx;#1;if(out_rgb!==ticker_reference[xx+1])$fatal(1,"ticker did not move exactly one pixel at %d",xx);end
  pixels=0;for(yy=448;yy<464;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin x=xx;y=yy;#1;if(out_rgb==24'hfff080)pixels=pixels+1;end
  if(pixels<300)$fatal(1,"missing Chinese glyphs (%d dots)",pixels);
  ticker_enable=0;frame();saved_phase=dut.ticker_phase;frame();
  if(saved_phase!=dut.ticker_phase)$fatal(1,"disabled ticker moved");
  pixel(10,451,rgb);
  wave_enable=0;error_code=8'h12;frame();pixel(100,380,rgb);pixel(100,46,24'hff6040);
  menu_item=6;transition_enable=0;frame();pixel(417,166,24'h40ffb0);
  if(dut.transition_q!==0)$fatal(1,"transition feedback missing");
  // Accelerated real clock: one second and minute rollover in the elapsed-time display.
  rst=1;repeat(2)@(negedge clk);rst=0;
  repeat(256*61)@(negedge clk);frame();
  if(dut.uptime!=24'h000101)$fatal(1,"UP timer minute carry failed %h",dut.uptime);
  // Save two complete RGB frames from the Verilog compositor for visual QA.
  brightness=-32;contrast=320;volume=8;source_width=1024;source_height=768;
  ticker_enable=1;wave_enable=1;error_code=0;menu_item=1;menu_active=1;frame();
  fh=$fopen("osd_menu.ppm.out","w");if(fh==0)$fatal(1,"cannot open raster artifact");
  $fwrite(fh,"P3\n640 480\n255\n");
  for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
   x=xx;y=yy;rgb={xx[7:0],yy[7:0],8'h60};
   wave_pixel=xx>=64&&xx<576&&(yy==378||yy==((xx>>3)&31)+362);#1;
   $fwrite(fh,"%0d %0d %0d\n",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
  end
  $fclose(fh);
  repeat(96)frame();menu_active=0;frame();
  fh=$fopen("osd_playback.ppm.out","w");if(fh==0)$fatal(1,"cannot open raster artifact");
  $fwrite(fh,"P3\n640 480\n255\n");
  for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
   x=xx;y=yy;rgb={xx[7:0],yy[7:0],8'h60};
   wave_pixel=xx>=64&&xx<576&&(yy==378||yy==((xx>>3)&31)+362);#1;
   $fwrite(fh,"%0d %0d %0d\n",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
  end
  $fclose(fh);
  $display("TEST PASS osd: full RGB raster artifacts, Chinese scrolling, alpha layers, font masks, frame snapshots, serial decimal formatting, error indicator, layer priority and elapsed timer");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
