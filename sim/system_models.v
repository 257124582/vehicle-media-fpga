`timescale 1ns/1ps
// BEHAVIORAL MODELS ONLY. These replace transport/storage/HDMI silicon in
// integration simulation; they are excluded from synthesis and the TD project.
module media_sys_pll(input refclk,input reset,output reg c0=0,output reg c1=0,output c2,output reg locked=0);
 always #5 c0=~c0;always #12.5 c1=~c1;assign c2=~c1;initial #1000 locked=1;
endmodule
module media_video_pll(input refclk,input reset,output reg pixel=0,output reg serial=0,output reg locked=0);
 always #20 pixel=~pixel;always #4 serial=~serial;initial #1000 locked=1;
endmodule
module sd_spi_reader #(parameter CLK_HZ=40000000,INIT_HALF=50,RUN_HALF=2,TIMEOUT=20000000)(
 input clk,input rst,input req,input [31:0] lba,output ready,output reg initialized=0,
 output reg byte_valid=0,output reg [7:0] byte_data,output reg [8:0] byte_index,
 output reg done=0,output reg failed=0,output reg [7:0] error_code=0,
 output cs_n,output sck,output mosi,input miso);
 integer fd,rc,index=-1;reg [7:0] sector[0:511];reg [7:0] startup=0;
 assign ready=initialized&&index<0;assign cs_n=1;assign sck=0;assign mosi=1;
 initial begin fd=$fopen("assets/fat32.img","rb");if(!fd)$fatal(1,"fixture missing");end
 always @(posedge clk)begin
  byte_valid<=0;done<=0;failed<=0;
  if(rst)begin initialized<=0;startup<=0;index=-1;end
  else begin
   if(!initialized)begin startup<=startup+1'b1;if(startup==99)initialized<=1;end
   if(req)begin if(!ready)$fatal(1,"SD request while busy");rc=$fseek(fd,lba*512,0);rc=$fread(sector,fd);
    if(rc!=512)$fatal(1,"out of card");index=0;
   end else if(index>=0)begin byte_valid<=1;byte_index<=index;byte_data<=sector[index];
    if(index==511)begin index=-1;done<=1;end else index=index+1;
   end
  end
 end
endmodule
module sdram_backend(input clk,input shifted_clk,input rst,output reg init_done=0,output reg refreshing=0,output busy,
 input we,input [20:0] wa,input [31:0] wd,input [3:0] wm,input re,input [20:0] ra,output rv,output [31:0] rd);
 reg [31:0] memory[0:2097151];reg [9:0] latency=0;reg [20:0] address[0:9];integer counter=0,j;
 assign rv=latency[9];assign rd=memory[address[9]];assign busy=0;
 always @(posedge clk)begin
  if(rst)begin init_done<=0;refreshing<=0;latency<=0;counter<=0;end
  else begin counter<=counter+1;if(counter>200)init_done<=1;refreshing<=counter%1250>1200;
   if(we&&re)$fatal(1,"read/write overlap");
   if(we)begin if(wm!=0)$fatal(1,"unexpected byte mask");memory[wa]<=wd;end
   latency<={latency[8:0],re};address[0]<=ra;for(j=1;j<10;j=j+1)address[j]<=address[j-1];
  end
 end
endmodule
module hdmi_1_4b_transmitter_core_wrapper #(parameter DEVICE="EG",HTOTAL=800,HSA=96,HFP=16,HBP=48,HACTIVE=640,
 VTOTAL=525,VSA=2,VFP=10,VBP=33,VACTIVE=480,VIDEO_VIC=1,VIDEO_TPG="Disable",VIDEO_FORMAT="RGB",AUDIO_SAMPLE_RATE="48K",IIC_SCL_DIV=250)(
 input I_pixel_clk,input I_rst,input I_edid_read_trig,output O_edid_read_valid,output [7:0] O_edid_read_data,
 input I_axis_s_user,input I_axis_s_valid,input I_axis_s_last,input [23:0] I_axis_s_data,output O_axis_s_ready,
 input I_audio_valid,input [23:0] I_audio_left_data,I_audio_right_data,input I_acr_valid,input [19:0] I_acr_cts,I_acr_n,
 output O_video_locked,output O_ddc_scl,inout IO_ddc_sda,output [9:0] O_ch0_tmds_data,O_ch1_tmds_data,O_ch2_tmds_data,O_clk_tmds_data);
 assign O_axis_s_ready=1;assign O_video_locked=!I_rst;assign O_ddc_scl=1;assign IO_ddc_sda=1'bz;
 assign O_edid_read_valid=0;assign O_edid_read_data=0;
 assign O_ch0_tmds_data=0;assign O_ch1_tmds_data=0;assign O_ch2_tmds_data=0;assign O_clk_tmds_data=0;
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="EG")(input I_pixel_clk,I_serial_clk,I_rst,
 input [9:0] ch0,ch1,ch2,chclk,output d0,d1,d2,dclk);
 assign d0=0;assign d1=0;assign d2=0;assign dclk=0;
endmodule
