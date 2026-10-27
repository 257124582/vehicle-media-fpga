`timescale 1ns/1ps
module vehicle_media_top(input clk,input rst_n,input key1,input key2,input key3,
 input sd_miso,output sd_dclk,output sd_mosi,output sd_ncs,input uart_rx,output uart_tx,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,output HDMI_CLK_P,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,
 output [7:0] seg_data,output [5:0] seg_sel,output [3:0] led);
 wire mem_clk,mem_shift,pixel_clk,serial_clk,unused_clk,sys_lock,video_lock;
 media_sys_pll u_sys_pll(clk,1'b0,unused_clk,mem_clk,mem_shift,sys_lock);
 media_video_pll u_video_pll(clk,1'b0,pixel_clk,serial_clk,video_lock);
 reg [19:0] power_count=0;always @(posedge clk)if(!power_count[19])power_count<=power_count+1'b1;
 wire arst=!rst_n||!power_count[19]||!sys_lock||!video_lock;
 wire mrst,prst;reset_sync u_mreset(mem_clk,arst,mrst);reset_sync u_preset(pixel_clk,arst,prst);
 wire rescan,rescan_busy,rescan_valid;wire [0:0] rescan_data;
 cdc_mailbox #(.WIDTH(1)) u_rescan(pixel_clk,prst,1'b1,rescan,rescan_busy,mem_clk,mrst,rescan_data,rescan_valid);
 wire retry_media;wire [1:0] retry_attempts;
 reg [4:0] restart_count;always @(posedge mem_clk or posedge mrst)
  if(mrst)restart_count<=16;else if(rescan_valid||retry_media)restart_count<=16;else if(restart_count!=0)restart_count<=restart_count-1'b1;
 wire media_rst=mrst||restart_count!=0;
 wire sd_ready,sd_initialized,sd_byte_valid,sd_done,sd_failed;wire [7:0] sd_byte,sd_error;wire [8:0] sd_index;
 media_retry u_retry(mem_clk,mrst,rescan_valid,sd_failed,sd_error,retry_media,retry_attempts);
 wire sector_req;wire [31:0] sector_lba;
 sd_spi_reader #(.CLK_HZ(40000000),.INIT_HALF(50),.RUN_HALF(2),.TIMEOUT(20000000)) u_sd(mem_clk,media_rst,sector_req,sector_lba,sd_ready,sd_initialized,
  sd_byte_valid,sd_byte,sd_index,sd_done,sd_failed,sd_error,sd_ncs,sd_dclk,sd_mosi,sd_miso);
 wire sdr_init,sdr_refresh,sdr_busy,wr_en,rd_en,rd_valid;wire [20:0] wr_addr,rd_addr;wire [31:0] wr_data,rd_data;wire [3:0] wr_mask;
 sdram_backend u_sdram(mem_clk,mem_shift,mrst,sdr_init,sdr_refresh,sdr_busy,wr_en,wr_addr,wr_data,wr_mask,rd_en,rd_addr,rd_valid,rd_data);
 reg scan_start,scan_started;always @(posedge mem_clk or posedge media_rst)
  if(media_rst)begin scan_start<=0;scan_started<=0;end else begin scan_start<=0;
   if(sd_initialized&&sdr_init&&!scan_started)begin scan_started<=1;scan_start<=1;end end
 wire file_begin,file_valid,file_last,file_ready,result_valid,result_ok;wire [31:0] file_size;wire [1:0] file_slot;wire [7:0] file_byte;
 wire [2:0] count_mem;wire scan_complete_mem;wire [7:0] media_error,debug_state;wire [15:0] skipped;
 reg [31:0] load_cycles;always @(posedge mem_clk or posedge media_rst)
  if(media_rst)load_cycles<=0;else if(scan_started&&!scan_complete_mem)load_cycles<=load_cycles+1'b1;
 fat32_media u_fat(mem_clk,media_rst,scan_start,sector_req,sector_lba,sd_ready,
  sd_byte_valid,sd_index,sd_byte,sd_done,sd_failed,file_begin,file_size,file_slot,file_valid,file_byte,file_last,file_ready,
  result_valid,result_ok,count_mem,scan_complete_mem,media_error,skipped,debug_state);
 wire pixel_valid,pixel_last,pixel_ready,bmp_done,bmp_error;wire [23:0] pixel_rgb;wire [20:0] pixel_offset;wire [7:0] bmp_code;wire [31:0] bmp_sum;
 wire [10:0] bmp_width,scaled_width;wire [9:0] bmp_height,scaled_height;
 wire write_complete;wire [31:0] write_sum,read_sum,read_timeouts;wire read_complete;wire [1:0] read_slot;wire [7:0] cache_error;
 bmp_stream u_bmp(mem_clk,media_rst,file_begin,file_size,file_valid,file_byte,file_last,file_ready,
  pixel_valid,pixel_rgb,pixel_offset,pixel_last,pixel_ready,bmp_done,bmp_error,bmp_code,bmp_sum,
  bmp_width,bmp_height,scaled_width,scaled_height);
 reg [31:0] source_size[0:3];reg [31:0] source_display_mem;integer size_index;
 always @(posedge mem_clk or posedge media_rst)begin
  if(media_rst)begin source_display_mem<=0;for(size_index=0;size_index<4;size_index=size_index+1)source_size[size_index]<=0;end
  else begin
   if(result_valid&&result_ok)source_size[file_slot]<={5'd0,bmp_width,6'd0,bmp_height};
   source_display_mem<=source_size[read_slot];
  end
 end
 assign result_valid=bmp_error||(bmp_done&&write_complete&&!pixel_valid);
 assign result_ok=!bmp_error&&write_complete;
 reg frame_request;reg [1:0] display_slot;reg fetch_enable;wire frame_ack,flush,fifo_we,fifo_full;wire [23:0] fifo_din,fifo_dout;wire [11:0] fifo_used;
 frame_cache u_cache(mem_clk,media_rst,file_begin,file_slot,pixel_valid,pixel_rgb,pixel_offset,pixel_last,pixel_ready,
  write_complete,write_sum,frame_request,display_slot,fetch_enable,frame_ack,flush,fifo_used,fifo_full,fifo_we,fifo_din,
  sdr_init,sdr_refresh,sdr_busy,wr_en,wr_addr,wr_data,wr_mask,rd_en,rd_addr,rd_valid,rd_data,
  read_timeouts,cache_error,read_complete,read_sum,read_slot);
 reg [31:0] writes[0:3],reads[0:3];reg [3:0] read_verified;reg write_stored,read_stored;integer j;
 always @(posedge mem_clk or posedge media_rst)begin
  if(media_rst)begin write_stored<=0;read_stored<=0;read_verified<=0;for(j=0;j<4;j=j+1)begin writes[j]<=0;reads[j]<=0;end end
  else begin
   if(file_begin)write_stored<=0;
   if(write_complete&&!write_stored)begin writes[file_slot]<=write_sum;write_stored<=1;end
   if(flush)read_stored<=0;
   if(read_complete&&!read_stored)begin reads[read_slot]<=read_sum;read_stored<=1;
    read_verified[read_slot]<=read_sum==writes[read_slot];end
  end
 end
 // A periodically refreshed bundled snapshot; never sample a live multibit count/checksum across clocks.
 reg [19:0] status_div;reg status_send;wire status_busy,status_valid;wire [241:0] status_bundle;
 wire [207:0] status_wide=status_bundle[207:0];wire [175:0] status_cross=status_wide[207:32];
 wire [31:0] source_display=status_bundle[239:208];
 wire [175:0] status_mem={7'd0,sdr_init,sd_initialized,scan_complete_mem,count_mem,read_verified,skipped,
  media_error,sd_error,cache_error,debug_state,writes[read_slot],reads[read_slot],read_timeouts,15'd0};
 always @(posedge mem_clk or posedge mrst)if(mrst)begin status_div<=0;status_send<=0;end
  else begin status_send<=0;status_div<=status_div+1'b1;if(status_div==0&&!status_busy)status_send<=1;end
 cdc_mailbox #(.WIDTH(242)) u_status(mem_clk,mrst,{retry_attempts,source_display_mem,status_mem,load_cycles},status_send,status_busy,pixel_clk,prst,status_bundle,status_valid);
 wire [2:0] count=status_cross[165:163];wire scan_complete=status_cross[166];
 reg reload_wait,reload_seen_clear;
 always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin reload_wait<=0;reload_seen_clear<=0;end
  else if(rescan)begin reload_wait<=1;reload_seen_clear<=0;end
  else if(status_valid&&reload_wait)begin
   if(!scan_complete)reload_seen_clear<=1;
   else if(reload_seen_clear)begin reload_wait<=0;reload_seen_clear<=0;end
  end
 end
 wire sd_ok=status_cross[167],sdr_ok=status_cross[168];
 wire [7:0] error_m=status_cross[142:135],error_sd=status_cross[134:127],error_cache=status_cross[126:119];
 wire [31:0] sum_w=status_cross[110:79],sum_r=status_cross[78:47];
 wire [10:0] rx_x;wire [9:0] rx_y;wire rx_de,frame_tick;
 video_raster u_raster(pixel_clk,prst,rx_x,rx_y,rx_de,frame_tick);
 wire next_press,auto_press,mode_press;
 wire uart_command_valid,control_reply_valid,reply_valid,reply_error;
 wire scene_reply_valid,scene_reply_error,play_reply_error;wire [4:0] uart_command;wire signed [15:0] uart_value;
 wire ui_command_valid;wire [4:0] ui_command;wire signed [15:0] ui_value;wire menu_active;wire [3:0] menu_item;
 wire command_valid=uart_command_valid||ui_command_valid;
 wire [4:0] command=uart_command_valid?uart_command:ui_command;
 wire signed [15:0] value=uart_command_valid?uart_value:ui_value;
 reg uart_pending;always @(posedge pixel_clk or posedge prst)if(prst)uart_pending<=0;else uart_pending<=uart_command_valid;
 assign reply_valid=(control_reply_valid||scene_reply_valid)&&uart_pending;
 assign reply_error=scene_reply_valid?scene_reply_error:play_reply_error;
 wire emergency,night_mode,technical,arrival,alert_trigger,arrival_trigger,hold_playback;
 wire emergency_toggle,night_toggle;wire [2:0] station;
 wire [31:0] emergency_count,recovery_count,response_cycles;
 wire scene_command=command>=17&&command<=21;
 vehicle_scene u_scene(pixel_clk,prst,frame_tick,emergency_toggle,night_toggle,
  command_valid&&scene_command,command,value,scene_reply_valid,scene_reply_error,
  emergency,night_mode,technical,station,arrival,alert_trigger,arrival_trigger,hold_playback,
  emergency_count,recovery_count,response_cycles);
 wire [1:0] image;wire autoplay,transition,compare,adaptive,audio_trigger;wire [5:0] period;wire [2:0] mode;
 wire [7:0] threshold;wire signed [8:0] brightness;wire [9:0] contrast;wire [3:0] volume;wire [4:0] alpha;
 wire continuous_test,ticker_enable,wave_enable;
 board_menu u_menu(pixel_clk,prst,key1,key2,key3,brightness,contrast,volume,ticker_enable,wave_enable,continuous_test,transition,
  !uart_command_valid,ui_command_valid,ui_command,ui_value,next_press,auto_press,mode_press,menu_active,menu_item,emergency,night_mode,technical,station,emergency_toggle,night_toggle);
 playback_control u_control(pixel_clk,prst,frame_tick,count,scan_complete&&!reload_wait,next_press,auto_press,mode_press,
  command_valid&&!scene_command,command,value,control_reply_valid,play_reply_error,rescan,image,autoplay,period,mode,threshold,brightness,contrast,volume,transition,compare,adaptive,alpha,audio_trigger,
  continuous_test,ticker_enable,wave_enable,hold_playback,night_mode);
 reg tick_delayed;always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin tick_delayed<=0;frame_request<=0;display_slot<=0;fetch_enable<=0;end
  else begin tick_delayed<=frame_tick;if(tick_delayed)begin frame_request<=~frame_request;display_slot<=image;fetch_enable<=scan_complete&&count!=0&&!reload_wait;end
   if(rescan)fetch_enable<=0;
  end
 end
 wire fw_rst,fr_rst;reset_sync u_fifo_wr_rst(mem_clk,media_rst||flush,fw_rst);
 reset_sync u_fifo_rd_rst(pixel_clk,media_rst||flush,fr_rst);
 wire fifo_empty;wire fifo_re=rx_de&&fetch_enable&&!fr_rst&&!reload_wait;
 async_fifo u_fifo(mem_clk,fw_rst,fifo_we,fifo_din,fifo_full,fifo_used,pixel_clk,fr_rst,fifo_re,fifo_dout,fifo_empty);
 reg de_delayed,available;reg [10:0] x_delayed;reg [9:0] y_delayed;reg [31:0] underflows;
 reg [23:0] diagnostic;
 always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin de_delayed<=0;available<=0;x_delayed<=0;y_delayed<=480;underflows<=0;diagnostic<=0;end
  else begin de_delayed<=rx_de;x_delayed<=rx_x;y_delayed<=rx_y;available<=fifo_re&&!fifo_empty;
   diagnostic<=rx_x<213?24'h202040:rx_x<426?24'h204020:24'h402020;
   if(fifo_re&&fifo_empty)underflows<=underflows+1'b1;
  end
 end
 wire vde;wire [10:0] vx;wire [9:0] vy;wire [23:0] vrgb,osd_rgb;wire [7:0] mean;wire [2:0] active_mode;
 image_pipeline u_image(pixel_clk,prst,de_delayed,x_delayed,y_delayed,available?fifo_dout:diagnostic,
  mode,threshold,brightness,contrast,5'd16,compare,adaptive,vde,vx,vy,vrgb,mean,active_mode);
 wire adjust_de;wire [10:0] adjust_x;wire [9:0] adjust_y;wire [23:0] adjust_rgb;
 // Slew image parameters at frame boundaries (up to ~0.3s for standard theme change).
 reg signed [8:0] applied_brightness;reg [9:0] applied_contrast;
 always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin applied_brightness<=0;applied_contrast<=256;end
  else if(frame_tick)begin
   if(applied_brightness<brightness)applied_brightness<=brightness-applied_brightness>3?applied_brightness+3:brightness;
   else if(applied_brightness>brightness)applied_brightness<=applied_brightness-brightness>3?applied_brightness-3:brightness;
   if(applied_contrast<contrast)applied_contrast<=contrast-applied_contrast>2?applied_contrast+2:contrast;
   else if(applied_contrast>contrast)applied_contrast<=applied_contrast-contrast>2?applied_contrast-2:contrast;
  end
 end
 color_adjust u_adjust(pixel_clk,prst,vde,vx,vy,vrgb,applied_brightness,applied_contrast,(active_mode==4||active_mode==5),alpha,
  adjust_de,adjust_x,adjust_y,adjust_rgb);
 reg final_de;reg [10:0] final_x;reg [9:0] final_y;reg [23:0] final_rgb;
 always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin final_de<=0;final_x<=0;final_y<=0;final_rgb<=0;end
  else begin final_de<=adjust_de;final_x<=adjust_x;final_y<=adjust_y;final_rgb<=adjust_rgb;end
 end
 wire audio_valid,acr_valid;wire [23:0] audio_l,audio_r;wire [19:0] acr_cts,acr_n;
 audio_pcm u_audio(pixel_clk,prst,alert_trigger||(!hold_playback&&(arrival_trigger||audio_trigger)),alert_trigger?2'd3:image,volume,audio_valid,audio_l,audio_r,acr_valid,acr_cts,acr_n,continuous_test&&!hold_playback);
 wire wave_pixel;
 audio_visualizer u_visual(pixel_clk,prst,frame_tick,audio_valid,audio_l,wave_enable,adjust_x,adjust_y,wave_pixel);
 wire overlay_enable=1'b1;
 wire osd_frame_tick=final_de&&final_x==639&&final_y==479;
 media_osd u_osd(pixel_clk,prst,osd_frame_tick,final_de,final_x,final_y,final_rgb,count,image,active_mode,autoplay,
  brightness,contrast,volume,menu_active,menu_item[2:0],ticker_enable,wave_enable,continuous_test,
  source_display[31:16],source_display[15:0],error_m|error_sd|error_cache,wave_pixel,osd_rgb,overlay_enable,transition,night_mode);
 wire media_ready=scan_complete&&count!=0&&!reload_wait;
 wire [7:0] media_state=error_cache!=0?8'd5:error_sd!=0?8'd4:error_m!=0?8'd3:
  reload_wait?8'd1:scan_complete?(count==0?8'd2:8'd6):!sd_ok?8'd0:8'd1;
 wire [23:0] vehicle_rgb;wire vehicle_de;wire [10:0] vehicle_x;wire [9:0] vehicle_y;
 vehicle_osd u_vehicle_osd(pixel_clk,prst,frame_tick,final_de,final_x,final_y,final_rgb,osd_rgb,
  emergency,night_mode,technical,station,arrival,menu_active,menu_item,brightness,contrast,volume,
  ticker_enable,wave_enable,continuous_test,transition,media_ready,media_state,count,
  error_m|error_sd|error_cache,wave_pixel,vehicle_de,vehicle_x,vehicle_y,vehicle_rgb);
 wire [191:0] vehicle_status={8'ha3,4'd0,arrival,technical,night_mode,emergency,5'd0,station,
  (station==5?8'hff:{5'd0,station}+8'd1),4'd0,menu_item,7'd0,hold_playback,7'd0,media_ready,
  media_state,emergency_count,recovery_count,response_cycles,32'd0};
 wire axis_ready,video_locked,edid_valid;wire [7:0] edid_byte;reg [26:0] edid_counter;reg edid_trigger;
 reg [31:0] ready_violations,display_frames;reg [7:0] edid_position,edid_sum;reg [63:0] edid_header;reg edid_ok;
 always @(posedge pixel_clk or posedge prst)begin
  if(prst)begin edid_counter<=0;edid_trigger<=0;ready_violations<=0;display_frames<=0;
   edid_position<=0;edid_sum<=0;edid_header<=0;edid_ok<=0;end
  else begin edid_trigger<=0;
   if(edid_counter==124999999)begin edid_counter<=0;edid_trigger<=1;end
   else begin edid_counter<=edid_counter+1'b1;if(edid_counter==2499999)edid_trigger<=1;end
   if(vehicle_de&&!axis_ready&&video_locked)ready_violations<=ready_violations+1'b1;
   if(vehicle_de&&vehicle_x==0&&vehicle_y==0)display_frames<=display_frames+1'b1;
   if(edid_trigger)begin edid_position<=0;edid_sum<=0;edid_header<=0;edid_ok<=0;end
   else if(edid_valid)begin
    edid_position<=edid_position+1'b1;edid_sum<=edid_sum+edid_byte;
    if(edid_position<8)edid_header<={edid_header[55:0],edid_byte};
    if(edid_position==127)edid_ok<=edid_header==64'h00ffffffffffff00&&((edid_sum+edid_byte)&8'hff)==0;
   end
  end
 end
 wire [191:0] console_status={8'ha1,edid_ok,video_locked,sd_ok,sdr_ok,scan_complete,autoplay,compare,adaptive,
  count,active_mode,image,error_m,error_sd,error_cache,2'b0,period,volume,4'b0,sum_w,sum_r,underflows,ready_violations};
 wire [191:0] console_detail={8'ha2,mean,2'b0,status_bundle[241:240],menu_active,continuous_test,wave_enable,ticker_enable,4'b0,status_cross[162:159],status_cross[118:111],
  2'b0,transition,alpha,threshold,2'b0,period,display_frames,status_wide[31:0],status_cross[46:15],
  status_cross[158:143],brightness[7:0],volume,transition,compare,adaptive,autoplay};
 uart_console u_console(pixel_clk,prst,uart_rx,uart_tx,uart_command_valid,uart_command,uart_value,reply_valid,reply_error,console_status,console_detail,vehicle_status);
 status_segments u_segments(pixel_clk,prst,{error_m,1'b0,count,1'b0,mode,1'b0,autoplay,image,volume},seg_data,seg_sel);
 assign led=~{(error_m!=0||error_sd!=0||error_cache!=0),scan_complete,autoplay,sd_ok};
 wire [9:0] ch0,ch1,ch2,chclk;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
  .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),.VIDEO_TPG("Disable"),
  .VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) u_hdmi(
  .I_pixel_clk(pixel_clk),.I_rst(prst),.I_edid_read_trig(edid_trigger),.O_edid_read_valid(edid_valid),.O_edid_read_data(edid_byte),
  .I_axis_s_user(vehicle_de&&vehicle_x==0&&vehicle_y==0),.I_axis_s_valid(vehicle_de),.I_axis_s_last(vehicle_de&&vehicle_x==639),.I_axis_s_data(vehicle_rgb),.O_axis_s_ready(axis_ready),
  .I_audio_valid(audio_valid),.I_audio_left_data(audio_l),.I_audio_right_data(audio_r),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),
  .O_video_locked(video_locked),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
  .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) u_phy(pixel_clk,serial_clk,prst,ch0,ch1,ch2,chclk,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P);
endmodule
