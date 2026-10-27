`timescale 1ns/1ps
// Read-only FAT32 root enumeration. One 512-byte cache; fragmented files are followed.
// Brent cycle detection bounds file chains without a large history RAM.
// Maximum file 4 MiB / 8192 clusters; root history remains bounded to 128.
module fat32_media(input clk,input rst,input start,
 output reg sector_req,output reg [31:0] sector_lba,input sector_ready,
 input sector_byte_valid,input [8:0] sector_byte_index,input [7:0] sector_byte,
 input sector_done,input sector_failed,
 output reg file_begin,output reg [31:0] file_size,output reg [1:0] file_slot,
 output file_valid,output [7:0] file_data,output file_last,input file_ready,
 input result_valid,input result_ok,
 output reg [2:0] image_count,output reg complete,output reg [7:0] error_code,
 output reg [15:0] skipped,output [7:0] debug_state);
 localparam OFF=0,REQ=1,WAIT_SECTOR=2,W1=3,W2=4,M_BEGIN=5,M_READ=6,M_WORD=7,M_VALIDATE=8,
 G1=9,G2=10,D_READ=11,D_WORD=12,D_EVAL=13,D_NEXT=14,D_FETCH=15,
 F_INIT=16,F_WORD=17,F_BYTES=18,F_RESULT=19,F_RESUME=20,
 N_READ=21,N_EVAL=22,V_SET=23,V_WAIT=24,V_CHECK=25,DONE=26,FAIL=27;
 reg [7:0] state,sector_return,word_return;
 reg [31:0] cache[0:127];reg [23:0] assemble;reg [6:0] read_addr;reg [31:0] read_word;
 reg [7:0] mount_index;reg [31:0] volume_base,partition_base,partition_length,volume_total,fat_sectors;
 reg [15:0] bps,reserved,root_entries,fat16,flags,fs_version,signature;
 reg [7:0] spc,fats;reg [3:0] spc_shift;reg [31:0] root_cluster;
 reg partition_found,using_partition;reg [7:0] part_type,partition_high_word;reg [15:0] part_low;
 reg [31:0] overhead,fat_base,data_base,cluster_count;reg [32:0] volume_end;
 reg [27:0] dir_cluster,file_cluster,entry_cluster,next_cluster;
 reg [7:0] dir_sector,file_sector;reg [3:0] dir_entry;reg [2:0] dir_word;
 reg [7:0] first_char,attrs;reg extension_bmp;reg [15:0] cluster_hi,cluster_lo;reg [31:0] entry_size;
 reg [31:0] file_position,file_word;reg [6:0] file_word_index;reg [1:0] byte_lane;
 reg lookup_file,file_auditing;reg [6:0] fat_word_index;
 (* ram_style="bram" *) reg [27:0] dir_history[0:127];
 reg [13:0] file_hops,file_cycle_power,file_cycle_length;
 reg [27:0] file_checkpoint;
 reg [7:0] dir_hops;reg [6:0] history_index;reg [27:0] dir_history_q;
 wire [27:0] history_data=dir_history_q;
 wire append_history=state==V_CHECK&&history_data!=next_cluster&&history_index+1==dir_hops;
 wire history_dir_we=!rst&&(state==G2||append_history);
 wire [6:0] history_dir_wa=state==G2?7'd0:dir_hops[6:0];
 wire [27:0] history_dir_wd=state==G2?root_cluster[27:0]:next_cluster;
 wire geometry_ok=(bps==512)&&(spc!=0)&&((spc&(spc-1'b1))==0)&&(spc<=128)&&
  (reserved!=0)&&(fats>=1&&fats<=2)&&(root_entries==0)&&(fat16==0)&&
  (fat_sectors!=0)&&(volume_total!=0)&&(fs_version==0)&&(signature==16'haa55);
 assign file_valid=state==F_BYTES;
 assign file_data=(file_word>>(byte_lane*8));
 assign file_last=file_position==file_size-1'b1;
 assign debug_state=state;
 function [3:0] log_spc;input [7:0] n;begin
  case(n)1:log_spc=0;2:log_spc=1;4:log_spc=2;8:log_spc=3;16:log_spc=4;32:log_spc=5;64:log_spc=6;128:log_spc=7;default:log_spc=0;endcase
 end endfunction
 function valid_cluster;input [27:0] c;begin valid_cluster=c>=2&&{4'b0,c}<cluster_count+2;end endfunction
 function [31:0] cluster_lba;input [27:0] c;input [7:0] sec;begin cluster_lba=data_base+((c-2)<<spc_shift)+sec;end endfunction
 task get_sector;input [31:0] addr;input [7:0] target;begin
  sector_lba<=addr;sector_return<=target;state<=REQ;
 end endtask
 task get_word;input [6:0] addr;input [7:0] target;begin read_addr<=addr;word_return<=target;state<=W1;end endtask
 task clear_bpb;begin bps<=0;spc<=0;reserved<=0;fats<=0;root_entries<=0;fat16<=0;
  fat_sectors<=0;volume_total<=0;root_cluster<=0;flags<=0;fs_version<=0;signature<=0;mount_index<=0;
 end endtask
 task fail;input [7:0] code;begin error_code<=code;state<=FAIL;complete<=1;end endtask
 task next_fat;input [27:0] c;input is_file;begin
  lookup_file<=is_file;fat_word_index<=c[6:0];get_sector(fat_base+(c>>7),N_READ);
 end endtask
 task reject_file;input [7:0] code;begin error_code<=code;skipped<=skipped+1'b1;state<=F_RESUME;end endtask
 always @(posedge clk) begin
  read_word<=cache[read_addr];
  dir_history_q<=dir_history[history_index];
  // One synchronous write port; do not reset RAM cells.
  if(history_dir_we)dir_history[history_dir_wa]<=history_dir_wd;
  if(sector_byte_valid) begin
   case(sector_byte_index[1:0])
    0:assemble[7:0]<=sector_byte;
    1:assemble[15:8]<=sector_byte;
    2:assemble[23:16]<=sector_byte;
    3:cache[sector_byte_index[8:2]]<={sector_byte,assemble};
   endcase
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=OFF;sector_req<=0;sector_lba<=0;sector_return<=0;word_return<=0;read_addr<=0;
   volume_base<=0;partition_base<=0;partition_length<=0;partition_found<=0;using_partition<=0;part_type<=0;part_low<=0;partition_high_word<=0;
   clear_bpb();overhead<=0;fat_base<=0;data_base<=0;cluster_count<=0;volume_end<=0;spc_shift<=0;
   dir_cluster<=0;file_cluster<=0;entry_cluster<=0;next_cluster<=0;dir_sector<=0;file_sector<=0;
   dir_entry<=0;dir_word<=0;first_char<=0;attrs<=0;extension_bmp<=0;cluster_hi<=0;cluster_lo<=0;entry_size<=0;
   file_position<=0;file_word<=0;file_word_index<=0;byte_lane<=0;lookup_file<=0;file_auditing<=0;fat_word_index<=0;
   file_hops<=0;file_cycle_power<=1;file_cycle_length<=0;file_checkpoint<=0;
   dir_hops<=0;history_index<=0;file_begin<=0;file_size<=0;file_slot<=0;
   image_count<=0;complete<=0;error_code<=0;skipped<=0;
  end else begin
   sector_req<=0;file_begin<=0;
   if(sector_failed&&state==WAIT_SECTOR) fail(8'h81);
   else case(state)
    OFF:if(start)begin clear_bpb();get_sector(0,M_BEGIN);end
    REQ:if(sector_ready)begin sector_req<=1;state<=WAIT_SECTOR;end
    WAIT_SECTOR:if(sector_done)state<=sector_return;
    W1:state<=W2;
    W2:state<=word_return;
    M_BEGIN:begin mount_index<=0;state<=M_READ;end
    M_READ:get_word(mount_index[6:0],M_WORD);
    M_WORD:begin
     case(mount_index)
      2:bps[7:0]<=read_word[31:24];
      3:begin bps[15:8]<=read_word[7:0];spc<=read_word[15:8];reserved<=read_word[31:16];end
      4:begin fats<=read_word[7:0];root_entries<=read_word[23:8];end
      5:fat16<=read_word[31:16];
      8:volume_total<=read_word;
      9:fat_sectors<=read_word;
      10:begin flags<=read_word[15:0];fs_version<=read_word[31:16];end
      11:root_cluster<=read_word;
      127:signature<=read_word[31:16];
     endcase
     if(!using_partition) begin
      if(mount_index==112||mount_index==116||mount_index==120||mount_index==124)part_type<=read_word[23:16];
      if(mount_index==113||mount_index==117||mount_index==121||mount_index==125)part_low<=read_word[31:16];
      if((mount_index==114||mount_index==118||mount_index==122||mount_index==126)&&!partition_found&&
        (part_type==8'h0b||part_type==8'h0c))begin
        partition_base<={read_word[15:0],part_low};partition_found<=1;partition_length[15:0]<=read_word[31:16];partition_high_word<=mount_index+1'b1;
      end
      if(mount_index==partition_high_word&&partition_found)
       partition_length[31:16]<=read_word[15:0];
     end
     if(mount_index==127)state<=M_VALIDATE;
     else begin mount_index<=mount_index+1'b1;state<=M_READ;end
    end
    M_VALIDATE:if(geometry_ok)begin
      if(flags[7]&&flags[3:0]>=fats)fail(8'h12);
      else begin overhead<=reserved+fats*fat_sectors;spc_shift<=log_spc(spc);state<=G1;end
     end else if(!using_partition&&signature==16'haa55&&partition_found&&partition_base!=0)begin
      volume_base<=partition_base;using_partition<=1;clear_bpb();get_sector(partition_base,M_BEGIN);
     end else fail(8'h11);
    G1:if(overhead>=volume_total)fail(8'h13);else begin
     cluster_count<=(volume_total-overhead)>>spc_shift;
     fat_base<=volume_base+reserved+(flags[7]?flags[3:0]*fat_sectors:0);
     data_base<=volume_base+overhead;volume_end<={1'b0,volume_base}+{1'b0,volume_total};state<=G2;
    end
    G2:if(cluster_count<65525||cluster_count>32'h0fffffed||fat_sectors<((cluster_count+129)>>7)||
       !valid_cluster(root_cluster[27:0])||root_cluster[31:28]!=0||volume_end[32]||
       (using_partition&&volume_total>partition_length))fail(8'h14);
     else begin dir_cluster<=root_cluster[27:0];dir_hops<=1;
      dir_sector<=0;dir_entry<=0;state<=D_FETCH;end
    D_FETCH:get_sector(cluster_lba(dir_cluster,dir_sector),D_READ);
    D_READ:begin dir_word<=0;get_word({dir_entry,3'b000},D_WORD);end
    D_WORD:begin
     case(dir_word)
      0:first_char<=read_word[7:0];
      2:begin attrs<=read_word[31:24];extension_bmp<=read_word[23:0]==24'h504d42;end
      5:cluster_hi<=read_word[15:0];
      6:cluster_lo<=read_word[31:16];
      7:begin entry_size<=read_word;entry_cluster<={cluster_hi[11:0],cluster_lo};end
     endcase
     if(dir_word==7)state<=D_EVAL;
     else begin dir_word<=dir_word+1'b1;get_word({dir_entry,3'b000}+dir_word+1'b1,D_WORD);end
    end
    D_EVAL:if(first_char==0)state<=DONE;
     else if(first_char==8'he5||attrs==8'h0f||attrs[4]||attrs[3]||!extension_bmp)state<=D_NEXT;
     else if(!valid_cluster(entry_cluster)||entry_size<54||entry_size>4194304||cluster_hi[15:12]!=0)begin
      skipped<=skipped+1'b1;error_code<=8'h41;state<=D_NEXT;
     end else begin
      file_begin<=1;file_size<=entry_size;file_slot<=image_count[1:0];file_position<=0;
      file_cluster<=entry_cluster;file_sector<=0;file_hops<=1;file_auditing<=0;
      file_checkpoint<=entry_cluster;file_cycle_power<=1;file_cycle_length<=0;
      get_sector(cluster_lba(entry_cluster,0),F_INIT);
     end
    D_NEXT:if(image_count==4)state<=DONE;
     else if(dir_entry<15)begin dir_entry<=dir_entry+1'b1;state<=D_READ;end
     else begin dir_entry<=0;
      if(dir_sector<spc-1'b1)begin dir_sector<=dir_sector+1'b1;state<=D_FETCH;end
      else next_fat(dir_cluster,0);
     end
    F_INIT:begin file_word_index<=0;get_word(0,F_WORD);end
    F_WORD:begin file_word<=read_word;byte_lane<=0;state<=F_BYTES;end
    F_BYTES:if(result_valid&&!result_ok)reject_file(8'h42);
     else if(file_ready)begin
      file_position<=file_position+1'b1;
      // Follow the remaining FAT links before accepting the frame. Brent may
      // discover a cycle after the declared byte count has already been read.
      // Auditing to EOC catches that case without storing every visited cluster.
      if(file_last)begin file_auditing<=1;next_fat(file_cluster,1);end
      else if(byte_lane!=3)byte_lane<=byte_lane+1'b1;
      else if(file_word_index!=127)begin file_word_index<=file_word_index+1'b1;get_word(file_word_index+1'b1,F_WORD);end
      else if(file_sector<spc-1'b1)begin file_sector<=file_sector+1'b1;
       get_sector(cluster_lba(file_cluster,file_sector+1'b1),F_INIT);end
      else next_fat(file_cluster,1);
     end
    F_RESULT:if(result_valid)begin
     if(result_ok)image_count<=image_count+1'b1;
     else begin skipped<=skipped+1'b1;error_code<=8'h42;end
     state<=F_RESUME;
    end
    F_RESUME:if(image_count==4)state<=DONE;
     else get_sector(cluster_lba(dir_cluster,dir_sector),D_NEXT);
    N_READ:get_word(fat_word_index,N_EVAL);
    N_EVAL:if(read_word[27:0]>=28'hffffff8)begin
      if(lookup_file)begin if(file_auditing)state<=F_RESULT;else reject_file(8'h43);end
      else state<=DONE;
     end else if(!valid_cluster(read_word[27:0]))begin
      if(lookup_file)reject_file(8'h44);else fail(8'h15);
     end else if((lookup_file&&file_hops>=8192)||(!lookup_file&&dir_hops>=128))begin
      if(lookup_file)reject_file(8'h45);else fail(8'h16);
     end else if(lookup_file)begin
      // Constant-space Brent detector. A rejected partial frame is never
      // committed. The independent hop bound also terminates hostile chains.
      if(read_word[27:0]==file_checkpoint)reject_file(8'h46);
      else begin
       if(file_cycle_length+1'b1==file_cycle_power)begin
        file_checkpoint<=read_word[27:0];file_cycle_power<=file_cycle_power<<1;
        file_cycle_length<=0;
       end else file_cycle_length<=file_cycle_length+1'b1;
       file_hops<=file_hops+1'b1;file_cluster<=read_word[27:0];file_sector<=0;
       if(file_auditing)next_fat(read_word[27:0],1);
       else get_sector(cluster_lba(read_word[27:0],0),F_INIT);
      end
     end else begin next_cluster<=read_word[27:0];history_index<=0;state<=V_SET;end
    V_SET:state<=V_WAIT;
    V_WAIT:state<=V_CHECK;
    V_CHECK:if(history_data==next_cluster)begin
      if(lookup_file)reject_file(8'h46);else fail(8'h17);
     end else if(history_index+1==dir_hops)begin
      dir_hops<=dir_hops+1'b1;
      dir_cluster<=next_cluster;dir_sector<=0;dir_entry<=0;state<=D_FETCH;
     end else begin history_index<=history_index+1'b1;state<=V_WAIT;end
    DONE:begin complete<=1;state<=DONE;if(image_count<4&&error_code==0)error_code<=8'h40;end
    FAIL:state<=FAIL;
    default:fail(8'hff);
   endcase
  end
 end
endmodule
