`timescale 1ns/1ps
// Sparse synthetic FAT32 card: maximum 4MiB on 512-byte clusters, late cycles,
// surplus allocation, short/bad chains, directory cycle and size rejection.
module tb_fat_large;
 reg clk=0,rst=1,start=0;always #4 clk=~clk;
 wire req;wire [31:0] lba;reg ready=1,bv=0,sd_done=0;reg [8:0] bi=0;reg [7:0] data=0;
 wire fb,fv,fl;wire [31:0] fsize;wire [1:0] slot;wire [7:0] fdata;
 wire [2:0] count;wire complete;wire [7:0] error,state;wire [15:0] skipped;
 reg result_valid=0;reg [15:0] stalls=16'habcd;wire fread=stalls[0]||stalls[3];
 fat32_media dut(clk,rst,start,req,lba,ready,bv,bi,data,sd_done,1'b0,fb,fsize,slot,
  fv,fdata,fl,fread,result_valid,1'b1,count,complete,error,skipped,state);
 reg [7:0] boot[0:511],directory[0:511];integer byte_index=-1;reg [31:0] active_lba;
 integer configured_size,chain_length,chain_mode,tests=0,received=0,expected_received;
 function [31:0] fat_entry;input integer c;begin
  fat_entry=0;
  if(c<2)fat_entry=32'h0fffffff;
  if(c==2)fat_entry=chain_mode==3?2:32'h0fffffff;
  if(chain_mode==1)begin if(c==3)fat_entry=4;if(c==4)fat_entry=3;end
  else if(chain_mode==2)begin if(c==3)fat_entry=32'h0ffffff7;end
  else if(c>=3&&c<3+chain_length)fat_entry=c==2+chain_length?32'h0fffffff:c+1;
 end endfunction
 function [7:0] card_byte;input [31:0] sector;input integer index;reg [31:0] word_value;begin
  if(sector==0)card_byte=boot[index];
  else if(sector==601)card_byte=directory[index];
  else if(sector>=1&&sector<=600)begin
   word_value=fat_entry((sector-1)*128+index/4);card_byte=word_value>>((index%4)*8);
  end else card_byte=(((sector-602)*512+index)*13+7)&255;
 end endfunction
 always @(posedge clk)begin
  bv<=0;sd_done<=0;stalls<={stalls[14:0],stalls[15]^stalls[13]^stalls[12]^stalls[10]};
  if(rst)begin byte_index=-1;ready<=1;result_valid<=0;received=0;end
  else begin
   if(req)begin
    if(byte_index!=-1)$fatal(1,"overlap request");active_lba=lba;byte_index=0;ready<=0;
   end else if(byte_index>=0)begin
    bv<=1;bi<=byte_index;data<=card_byte(active_lba,byte_index);
    if(byte_index==511)begin byte_index=-1;ready<=1;sd_done<=1;end else byte_index=byte_index+1;
   end
   if(fb)begin result_valid<=0;received=0;if(fsize!=configured_size)$fatal(1,"size metadata");end
   if(fv&&fread)begin
    if(fdata!==((received*13+7)&255)&&chain_mode==0)$fatal(1,"data mismatch at %d",received);
    received=received+1;
    if(fl)begin if(received!=configured_size)$fatal(1,"wrong last");result_valid<=1;end
   end
  end
 end
 task boot32;input integer at;input [31:0] value;integer k;begin for(k=0;k<4;k=k+1)boot[at+k]=value>>(k*8);end endtask
 task dir32;input integer at;input [31:0] value;integer k;begin for(k=0;k<4;k=k+1)directory[at+k]=value>>(k*8);end endtask
 task check_case;input integer size,length,mode,expect_count,expect_skipped,expect_error;
  integer k;
  begin
   @(negedge clk);rst=1;configured_size=size;chain_length=length;chain_mode=mode;
   for(k=0;k<512;k=k+1)begin boot[k]=0;directory[k]=0;end
   boot[11]=0;boot[12]=2;boot[13]=1;boot[14]=1;boot[16]=1;boot32(32,70000);boot32(36,600);boot32(44,2);
   boot[510]=8'h55;boot[511]=8'haa;
   directory[0]=8'h46;directory[8]=8'h42;directory[9]=8'h4d;directory[10]=8'h50;
   directory[11]=8'h20;directory[26]=3;dir32(28,size);
   if(mode==3)for(k=0;k<16;k=k+1)directory[k*32]=8'he5;
   repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
   wait(complete);@(negedge clk);
   if(count!=expect_count||skipped!=expect_skipped||error!=expect_error)$fatal(1,"FAT case %0d count=%d skipped=%d err=%h expected=%h",tests,count,skipped,error,expect_error);
   if(expect_count&&received!=size)$fatal(1,"wrong received %d",received);
   tests=tests+1;$display("FAT case %0d passed bytes=%0d allocatedclusters=%0d mode=%0d err=%h",tests,size,length,mode,error);
  end
 endtask
 initial begin
  check_case(4194304,8192,0,1,0,8'h40);
  check_case(1049088,2049,0,1,0,8'h40);
  check_case(4194305,8193,0,0,1,8'h41);
  check_case(1024,2,1,0,1,8'h46);
  check_case(1536,2,0,0,1,8'h43);
  check_case(1024,2,2,0,1,8'h44);
  check_case(512,3,0,1,0,8'h40);
  check_case(512,1,3,0,0,8'h17);
  $display("TEST PASS fat_large: 4MiB /8192clusters accepted, >2048 clusters, lateEOFcycle rejected, short/bad chains, excess allocation and rootcycle");$finish;
 end
 initial begin #300000000;$fatal(1,"fat_large timeout state=%d received=%d",state,received);end
endmodule
