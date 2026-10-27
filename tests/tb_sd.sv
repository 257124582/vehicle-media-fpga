`timescale 1ns/1ps
module tb_sd;
 reg clk=0;always #4 clk=~clk;reg rst=1,req=0;wire ready,initialized,bv,done,failed,cs,sck,mosi;
 wire [7:0] data,error;wire [8:0] index;reg [7:0] tx_shift=255,rx_shift=0;
 reg [7:0] queue[0:2047];integer head=0,tail=0,bits=0,command_bytes=0,retries=0,received=0,commands=0;
 reg [47:0] packet=0;integer bad_crc=0,bad_ccs=0,silent=0,stuck_c0=0;reg card_ready=0;
 wire miso=cs?1'b1:tx_shift[7];
 sd_spi_reader #(.INIT_HALF(2),.RUN_HALF(1),.TIMEOUT(100000)) dut(clk,rst,req,32'd1234,ready,initialized,bv,data,index,done,failed,error,cs,sck,mosi,miso);
 function [6:0] crc7;input [39:0] m;integer j;reg [6:0] c;begin c=0;
  for(j=39;j>=0;j=j-1)begin if(c[6]^m[j])c=(c<<1)^7'h09;else c=c<<1;end crc7=c;end endfunction
 function [15:0] crcbyte;input [15:0] c0;input [7:0] b;integer j;reg [15:0] c;begin
  c=c0^{b,8'b0};for(j=0;j<8;j=j+1)c=c[15]?(c<<1)^16'h1021:c<<1;crcbyte=c;end endfunction
 task push;input [7:0] b;begin queue[tail]=b;tail=tail+1;end endtask
 task respond;input [47:0] p;integer i;reg [15:0] c;begin
  commands=commands+1;
  if(p[7:1]!==crc7(p[47:8])||!p[0])$fatal(1,"command CRC %h",p);
  if(!silent)case(p[45:40])
   0:begin card_ready=0;push(stuck_c0?0:1);end
   8:begin push(1);push(0);push(0);push(1);push(8'haa);end
   55:push(card_ready?0:1);
   41:begin retries=retries+1;if(retries>=3)card_ready=1;push(card_ready?0:1);end
   58:begin push(0);push(bad_ccs?8'h80:8'hc0);push(8'hff);push(8'h80);push(0);end
   59:begin if(p[39:8]!=1)$fatal(1,"CMD59 must enable CRC");push(0);end
   17:begin
    if(p[39:8]!=1234)$fatal(1,"SDHC LBA was converted to byte address");
    push(0);push(255);push(8'hfe);c=0;
    for(i=0;i<512;i=i+1)begin push((i*7+3)&255);c=crcbyte(c,(i*7+3)&255);end
    push(c[15:8]);push(c[7:0]^bad_crc);
   end
   default:$fatal(1,"unsupported outgoing command %d",p[45:40]);
  endcase
 end endtask
 always @(posedge cs)begin bits=0;command_bytes=0;head=0;tail=0;tx_shift=255;end
 always @(posedge sck)if(!cs)begin
  rx_shift={rx_shift[6:0],mosi};bits=bits+1;
  if(bits==8)begin bits=0;
   if(command_bytes!=0||rx_shift[7:6]==2'b01)begin
    packet={packet[39:0],rx_shift};command_bytes=command_bytes+1;
    if(command_bytes==6)begin command_bytes=0;respond(packet);end
   end
  end
 end
 always @(negedge sck)if(!cs)begin
  if(bits==0)begin if(head<tail)begin tx_shift=queue[head];head=head+1;end else tx_shift=255;end
  else tx_shift={tx_shift[6:0],1'b1};
 end
 always @(posedge clk)if(bv)begin
  if(index!==received||data!==((received*7+3)&255))$fatal(1,"sector byte %d index=%d data=%h",received,index,data);
  received=received+1;
 end
 task reboot;begin rst=1;received=0;retries=0;repeat(6)@(negedge clk);rst=0;end endtask
 initial begin
  reboot();wait(ready);@(negedge clk);req=1;@(negedge clk);req=0;wait(done);
  if(received!=512||error!=0)$fatal(1,"read incomplete");
  bad_crc=1;reboot();wait(ready);@(negedge clk);req=1;@(negedge clk);req=0;wait(failed);
  if(error!=9||initialized)$fatal(1,"bad CRC accepted %h",error);
  bad_crc=0;bad_ccs=1;reboot();wait(failed);if(error!=5)$fatal(1,"SDSC accepted");
  bad_ccs=0;stuck_c0=1;reboot();wait(failed);if(error!=4)$fatal(1,"CMD0 retries unbounded");
  stuck_c0=0;silent=1;reboot();wait(failed);if(error!=1)$fatal(1,"missing timeout");
  $display("TEST PASS SD: command CRC7, bounded CMD0 retries, 3 ACMD41 retries, block addressing, all 512 bytes, CRC16 rejection, CCS rejection, timeout; commands=%d",commands);$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
