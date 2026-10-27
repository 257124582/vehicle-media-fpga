`timescale 1ns/1ps
// SD v2 SDHC/SDXC, SPI mode 0, read-only. CMD59 enables command/data CRC.
module sd_spi_reader #(parameter CLK_HZ=125000000,parameter INIT_HALF=313,parameter RUN_HALF=3,
 parameter TIMEOUT=62500000)(
 input clk,input rst,input req,input [31:0] lba,output ready,output reg initialized,
 output reg byte_valid,output reg [7:0] byte_data,output reg [8:0] byte_index,
 output reg done,output reg failed,output reg [7:0] error_code,
 output reg cs_n,output sck,output mosi,input miso);
 localparam POWER=0,I0=1,I8=2,I55=3,I41=4,I58=5,I59=6,IDLE=7,
  C_PRE=8,C_SEND=9,C_RESP=10,C_EXTRA=11,R_TOKEN=12,R_DATA=13,R_CRC1=14,R_CRC2=15,R_END=16,FAULT=17;
 reg [4:0] state,ret;
 reg spi_go;reg [7:0] spi_tx;wire spi_busy,spi_done;wire [7:0] spi_rx;
 reg [15:0] half_period;
 reg [47:0] packet;reg [2:0] command_byte,extra_count;
 reg [7:0] response;reg [31:0] extra;
 reg [31:0] watchdog;reg [10:0] init_retries;reg [3:0] power_bytes;
 reg [15:0] crc16;reg [7:0] crc_hi;reg [31:0] address;reg [8:0] data_count;
 wire waiting=(state!=IDLE&&state!=FAULT);
 assign ready=initialized&&state==IDLE;
 spi_byte u_spi(clk,rst,spi_go,spi_tx,half_period,miso,sck,mosi,spi_busy,spi_done,spi_rx);
 function [6:0] crc7;input [39:0] msg;integer j;reg [6:0] c;reg feedback;begin
  c=0;for(j=39;j>=0;j=j-1) begin feedback=c[6]^msg[j];c={c[5:0],1'b0};if(feedback)c=c^7'h09;end
  crc7=c;end endfunction
 function [15:0] crc_byte;input [15:0] prior;input [7:0] b;integer j;reg [15:0] c;begin
  c=prior^{b,8'h00};for(j=0;j<8;j=j+1)c=c[15]?(c<<1)^16'h1021:(c<<1);
  crc_byte=c;end endfunction
 task command;input [5:0] id;input [31:0] arg;input [2:0] ext_len;input [4:0] target;
  reg [39:0] message;begin
   message={2'b01,id,arg};packet<={message,crc7(message),1'b1};
   command_byte<=0;extra_count<=ext_len;extra<=0;response<=8'hff;ret<=target;
   cs_n<=1;state<=C_PRE;watchdog<=0;
  end endtask
 task transfer;input [7:0] value;begin if(!spi_busy&&!spi_go&&!spi_done)begin spi_go<=1;spi_tx<=value;end end endtask
 task fault;input [7:0] code;begin state<=FAULT;cs_n<=1;failed<=1;error_code<=code;initialized<=0;end endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=POWER;ret<=0;spi_go<=0;spi_tx<=255;half_period<=INIT_HALF;
   packet<=0;command_byte<=0;extra_count<=0;response<=255;extra<=0;watchdog<=0;init_retries<=0;
   power_bytes<=0;crc16<=0;crc_hi<=0;address<=0;initialized<=0;byte_valid<=0;byte_data<=0;
   byte_index<=0;data_count<=0;done<=0;failed<=0;error_code<=0;cs_n<=1;
  end else begin
   spi_go<=0;byte_valid<=0;done<=0;failed<=0;
   if(waiting) watchdog<=watchdog+1'b1;else watchdog<=0;
   if(waiting&&watchdog>=TIMEOUT) fault(8'h01);
   else case(state)
    POWER:begin transfer(255);if(spi_done)begin if(power_bytes==9) command(0,0,0,I0);else power_bytes<=power_bytes+1'b1;end end
    I0:if(response==1)begin init_retries<=0;command(8,32'h1aa,4,I8);end
     else if(init_retries<1023)begin init_retries<=init_retries+1'b1;command(0,0,0,I0);end
     else fault(8'h04);
    I8:if(response!=1||extra[11:0]!=12'h1aa)fault(8'h02);else command(55,0,0,I55);
    I55:if(response>1)fault(8'h03);else command(41,32'h40000000,0,I41);
    I41:if(response==0)command(58,0,4,I58);
     else if(response==1&&init_retries<1023)begin init_retries<=init_retries+1'b1;command(55,0,0,I55);end
     else fault(8'h04);
    I58:if(response!=0||!extra[31]||!extra[30]||(extra[23:15]==0))fault(8'h05);
     else command(59,1,0,I59);
    I59:if(response!=0)fault(8'h06);else begin initialized<=1;half_period<=RUN_HALF;state<=IDLE;cs_n<=1;end
    IDLE:if(req)begin address<=lba;command(17,lba,0,R_TOKEN);end
    C_PRE:begin transfer(255);if(spi_done)begin cs_n<=0;state<=C_SEND;end end
    C_SEND:begin transfer(packet[47:40]);if(spi_done)begin packet<={packet[39:0],8'hff};
     if(command_byte==5)state<=C_RESP;else command_byte<=command_byte+1'b1;end end
    C_RESP:begin transfer(255);if(spi_done&&!spi_rx[7])begin response<=spi_rx;
     if(extra_count!=0)state<=C_EXTRA;else begin state<=ret;if(ret!=R_TOKEN)cs_n<=1;end end end
    C_EXTRA:begin transfer(255);if(spi_done)begin extra<={extra[23:0],spi_rx};
     extra_count<=extra_count-1'b1;if(extra_count==1)begin state<=ret;cs_n<=1;end end end
    R_TOKEN:if(response!=0)fault(8'h07);else begin transfer(255);
     if(spi_done)begin if(spi_rx==8'hfe)begin state<=R_DATA;data_count<=0;crc16<=0;end
      else if(spi_rx!=255)fault(8'h08);end end
    R_DATA:begin transfer(255);if(spi_done)begin byte_valid<=1;byte_data<=spi_rx;byte_index<=data_count;crc16<=crc_byte(crc16,spi_rx);
     if(data_count==511)state<=R_CRC1;else data_count<=data_count+1'b1;end end
    R_CRC1:begin transfer(255);if(spi_done)begin crc_hi<=spi_rx;state<=R_CRC2;end end
    R_CRC2:begin transfer(255);if(spi_done)begin cs_n<=1;
     if({crc_hi,spi_rx}!=crc16)fault(8'h09);else state<=R_END;end end
    R_END:begin transfer(255);if(spi_done)begin done<=1;state<=IDLE;end end
    FAULT:cs_n<=1;
    default:fault(8'hff);
   endcase
  end
 end
endmodule
