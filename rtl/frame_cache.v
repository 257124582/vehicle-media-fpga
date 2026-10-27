`timescale 1ns/1ps
// Application-side SDRAM arbitration. Four-word aligned writes, 128-word reads.
// No simultaneous read/write; all returned read words drain before a write begins.
module frame_cache #(parameter FRAME_WORDS=307200,parameter BURST=128)(
 input clk,input rst,input begin_file,input [1:0] write_slot,
 input pixel_valid,input [23:0] pixel_rgb,input [20:0] pixel_offset,input pixel_last,output pixel_ready,
 output reg write_complete,output reg [31:0] write_checksum,
 input frame_toggle,input [1:0] display_slot,input fetch_enable,output reg frame_ack,
 output reg fifo_flush,input [11:0] fifo_used,input fifo_full,output fifo_we,output [23:0] fifo_data,
 input init_done,input refreshing,input sdram_busy,
 output app_wr_en,output [20:0] app_wr_addr,output [31:0] app_wr_data,output [3:0] app_wr_mask,
 output app_rd_en,output [20:0] app_rd_addr,input read_valid,input [31:0] read_data,
 output reg [31:0] read_timeouts,output reg [7:0] fault_code,
 output reg read_complete,output reg [31:0] read_checksum,output reg [1:0] read_slot);
 localparam IDLE=0,FLUSH=1,SETTLE=2,READ=3,R_TAIL=4,WRITE=5,W_TAIL=6;
 reg [2:0] state;reg [2:0] fill;reg [31:0] words[0:3];reg [20:0] write_address,write_base;
 reg group_last,do_fetch;reg [1:0] wi;reg [8:0] issued,received;
 reg [20:0] read_base,read_position;reg [9:0] wait_count;
 (* async_reg="true" *) reg [1:0] req_sync;
 assign pixel_ready=fill<4;
 assign app_wr_en=state==WRITE;
 assign app_wr_addr=write_address+wi;
 assign app_wr_data=words[wi];
 assign app_wr_mask=4'b0000;
 assign app_rd_en=state==READ&&issued<BURST;
 assign app_rd_addr=read_base+read_position+issued;
 assign fifo_we=state==READ&&read_valid&&!fifo_full;
 assign fifo_data=read_data[31:8];
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;fill<=0;write_address<=0;write_base<=0;group_last<=0;wi<=0;issued<=0;received<=0;
   read_base<=0;read_position<=FRAME_WORDS;do_fetch<=0;req_sync<=0;frame_ack<=0;fifo_flush<=0;
   wait_count<=0;write_complete<=0;write_checksum<=0;read_timeouts<=0;fault_code<=0;read_complete<=0;read_checksum<=0;read_slot<=0;
  end else begin
   req_sync<={req_sync[0],frame_toggle};
   if(begin_file)begin fill<=0;write_base<=write_slot*FRAME_WORDS;write_complete<=0;write_checksum<=0;group_last<=0;end
   else if(pixel_valid&&pixel_ready)begin
    words[fill[1:0]]<={pixel_rgb,8'b0};fill<=fill+1'b1;
    if(fill==0)begin write_address<=write_base+pixel_offset;if(pixel_offset[1:0]!=0)fault_code<=8'h51;end
    else if(write_base+pixel_offset!=write_address+fill)fault_code<=8'h52;
    if(pixel_last)group_last<=1;
   end
   case(state)
    IDLE:if(req_sync[1]!=frame_ack)begin
      read_base<=display_slot*FRAME_WORDS;read_position<=0;do_fetch<=fetch_enable;
      read_checksum<=0;read_complete<=0;read_slot<=display_slot;
      fifo_flush<=1;wait_count<=0;state<=FLUSH;
     end else if(init_done&&!refreshing&&!sdram_busy)begin
      if(do_fetch&&read_position<FRAME_WORDS&&fifo_used<=1920&&(fifo_used<512||fill<4))begin
       issued<=0;received<=0;wait_count<=0;state<=READ;
      end else if(fill==4)begin wi<=0;state<=WRITE;end
     end
    FLUSH:if(wait_count==7)begin fifo_flush<=0;wait_count<=0;state<=SETTLE;end else wait_count<=wait_count+1'b1;
    SETTLE:if(wait_count==23)begin frame_ack<=req_sync[1];state<=IDLE;end else wait_count<=wait_count+1'b1;
    READ:begin
     wait_count<=wait_count+1'b1;
     if(app_rd_en)issued<=issued+1'b1;
     if(read_valid)begin received<=received+1'b1;read_checksum<=read_checksum+read_data[31:8];if(fifo_full)fault_code<=8'h53;
      if(received==BURST-1)begin read_position<=read_position+BURST;wait_count<=0;state<=R_TAIL;
       if(read_position+BURST==FRAME_WORDS)read_complete<=1;end
     end
     if(wait_count==999)begin read_timeouts<=read_timeouts+1'b1;fault_code<=8'h54;do_fetch<=0;state<=R_TAIL;wait_count<=0;end
    end
    R_TAIL:if(wait_count==11)state<=IDLE;else wait_count<=wait_count+1'b1;
    WRITE:begin
     write_checksum<=write_checksum+words[wi][31:8];
     if(wi==3)begin wait_count<=0;state<=W_TAIL;end else wi<=wi+1'b1;
    end
    W_TAIL:if(wait_count==11)begin fill<=0;state<=IDLE;if(group_last)begin write_complete<=1;group_last<=0;end end
     else wait_count<=wait_count+1'b1;
    default:state<=IDLE;
   endcase
  end
 end
endmodule

`ifndef SIM_MEMORY_MODEL
module sdram_backend(input clk,input shifted_clk,input rst,output init_done,output refreshing,output busy,
 input we,input [20:0] wa,input [31:0] wd,input [3:0] wm,input re,input [20:0] ra,
 output rv,output [31:0] rd);
 wire sclk,ras_n,cas_n,we_n;wire [1:0] ba;wire [10:0] addr;wire [3:0] dm;wire [31:0] dq;
 wire [31:0] controller_rd;reg [31:0] aligned_rd;
 reg [1:0] refresh_guard;
 wire auto_refresh=!ras_n&&!cas_n&&we_n;
 wire suppress_refresh=auto_refresh&&(refresh_guard!=0);
 // The supplied core can hold AUTO REFRESH for two clocks when an idle gap
 // coincides with its refresh deadline. Send NOP for the repeated command:
 // IS42S32200 needs at least 70 ns between refresh commands (3 x 25 ns here).
 // Commands are sampled by the SIP on the following shifted-clock edge.
 always @(posedge clk or posedge rst)
  if(rst)refresh_guard<=0;
  else if(auto_refresh&&refresh_guard==0)refresh_guard<=2;
  else if(refresh_guard!=0)refresh_guard<=refresh_guard-1'b1;
 // At 40 MHz / 180 degrees the supplied controller's data leads its valid by
 // one cycle. APUG011 explicitly requires phase-dependent read alignment.
 // Capture continuously so the first word is retained before rv asserts.
 always @(posedge clk or posedge rst)
  if(rst)aligned_rd<=0;else aligned_rd<=controller_rd;
 assign rd=aligned_rd;
 sdr_as_ram #(.self_refresh_open(1'b1)) u_controller(
  .Sdr_clk(clk),.Sdr_clk_sft(shifted_clk),.Rst(rst),.Sdr_init_done(init_done),.Sdr_init_ref_vld(refreshing),.Sdr_busy(busy),
  .App_ref_req(1'b0),.App_wr_en(we),.App_wr_addr(wa),.App_wr_dm(wm),.App_wr_din(wd),
  .App_rd_en(re),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(controller_rd),
  .SDRAM_CLK(sclk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),.SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
 EG_PHY_SDRAM_2M_32 u_memory(.clk(sclk),.ras_n(ras_n||suppress_refresh),.cas_n(cas_n||suppress_refresh),.we_n(we_n),.addr(addr),.ba(ba),.dq(dq),
  .cs_n(1'b0),.dm0(dm[0]),.dm1(dm[1]),.dm2(dm[2]),.dm3(dm[3]),.cke(1'b1));
endmodule
`endif
