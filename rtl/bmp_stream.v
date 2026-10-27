`timescale 1ns/1ps
// Read-only 24-bit BI_RGB BMP loader and bounded, load-time bilinear scaler.
// Two source rows, Q12 coordinates / Q8 coefficients. One registered 9x9
// multiply is shared between R/G/B and both interpolation directions.
// The original positional ports are preserved; dimension metadata is appended.
module bmp_stream #(parameter WIDTH=640,HEIGHT=480)(input clk,input rst,input begin_file,input [31:0] file_size,
 input in_valid,input [7:0] in_byte,input in_last,output in_ready,
 output reg pixel_valid,output reg [23:0] pixel_rgb,output reg [20:0] pixel_offset,
 output reg pixel_last,input pixel_ready,output reg done,output reg error,output reg [7:0] error_code,
 output reg [31:0] checksum,output reg [10:0] source_width,output reg [9:0] source_height,
 output reg [10:0] scaled_width,output reg [9:0] scaled_height);
 localparam HEAD=0,CHECK=1,SIZE=2,FIT=3,FIT_RESULT=4,X_STEP=5,X_RESULT=6,
  Y_STEP=7,Y_RESULT=8,ROW=9,READ=10,EMIT=11,FETCH0=12,FETCH1=13,
  CAPTURE=14,LERP_LOAD=15,LERP_MUL=16,LERP_ADD=17,OUTPUT_PIXEL=18,
  DRAIN=19,DIVIDE=20,FINISHED=21,FAILED=22;
 reg [4:0] state,div_return;
 reg [31:0] pos,bf_size,offset,dib,width,height,compression,size_latched;
 reg [15:0] magic,planes,bits;
 reg top_down,fit_width_limited,input_ended;
 reg [11:0] row_bytes,row_stride,row_byte;
 reg [31:0] required_size;
 reg [9:0] size_rows,loaded_rows,load_row;
 reg [9:0] load_x;
 reg [1:0] phase;
 reg [7:0] b,g;
 reg [10:0] ox,dx;
 reg [9:0] oy,dy;
 reg [10:0] pad_x;
 reg [9:0] pad_y;
 reg [31:0] x_step,y_step,x_coord,y_coord;
 reg [31:0] div_num,div_den,div_quot;
 reg [32:0] div_rem;
 reg [5:0] div_count;
 wire [32:0] div_trial={div_rem[31:0],div_num[31]};
 wire div_ge=div_trial>={1'b0,div_den};
 wire [31:0] div_next_quot={div_quot[30:0],div_ge};
 wire [31:0] abs_height=height[31]?(~height+1'b1):height;
 wire [31:0] header_row_bytes=(width<<1)+width;
 wire [31:0] header_stride=(header_row_bytes+3)&32'hfffffffc;
 // Expand parameter constants explicitly. TD otherwise spends DSP blocks on
 // the aspect-ratio cross products and even y*640, in addition to the lerp.
 function [31:0] times_width;input [10:0] value;integer k;reg [31:0] accum;begin
  accum=0;for(k=0;k<16;k=k+1)if((WIDTH>>k)&1)accum=accum+({21'b0,value}<<k);
  times_width=accum;
 end endfunction
 function [31:0] times_height;input [10:0] value;integer k;reg [31:0] accum;begin
  accum=0;for(k=0;k<16;k=k+1)if((HEIGHT>>k)&1)accum=accum+({21'b0,value}<<k);
  times_height=accum;
 end endfunction
 wire base_header_ok=magic==16'h4d42&&dib>=40&&dib<=4096&&
  width>=1&&width<=1024&&abs_height>=1&&abs_height<=768&&
  planes==1&&bits==24&&compression==0&&offset>=14+dib&&offset<=4096&&
  bf_size<=size_latched&&size_latched<=4194304;
 wire can_put=!pixel_valid||pixel_ready;
 assign in_ready=!error&&!done&&!input_ended&&
  ((state==HEAD&&pos<54)||state==READ||state==DRAIN);
 wire taking=in_valid&&in_ready;
 wire active_row=oy>=pad_y&&oy<pad_y+scaled_height;
 wire active_col=ox>=pad_x&&ox<pad_x+scaled_width;
 wire [9:0] sy=(scaled_height>1&&dy==scaled_height-1)?source_height-1:y_coord[21:12];
 wire [9:0] sy1=sy<source_height-1?sy+1'b1:sy;
 wire [9:0] sx=(scaled_width>1&&dx==scaled_width-1)?source_width-1:x_coord[21:12];
 wire [9:0] sx1=sx<source_width-1?sx+1'b1:sx;
 wire [7:0] fx=(scaled_width>1&&dx==scaled_width-1)?0:x_coord[11:4];
 wire [7:0] fy=(scaled_height>1&&dy==scaled_height-1)?0:y_coord[11:4];
 (* ram_style="bram" *) reg [23:0] row0[0:1023];
 (* ram_style="bram" *) reg [23:0] row1[0:1023];
 reg [9:0] read_x;
 reg [23:0] row0_q,row1_q,p00,p01,p10,p11,rendered;
 reg [1:0] channel,lerp_stage;
 reg [7:0] h0,h1,lerp_base;
 reg signed [8:0] lerp_delta,lerp_weight;
 reg signed [17:0] lerp_product;
 wire signed [18:0] lerp_sum=$signed({1'b0,lerp_base,8'b0})+
  $signed(lerp_product)+19'sd128;
 wire [7:0] lerp_value=lerp_sum[15:8];
 wire ram_we=taking&&state==READ&&pos>=offset&&row_byte<row_bytes&&phase==2;
 always @(posedge clk)begin
  row0_q<=row0[read_x];row1_q<=row1[read_x];
  if(ram_we)begin
   if(load_row[0])row1[load_x]<={in_byte,g,b};
   else row0[load_x]<={in_byte,g,b};
  end
 end
 task divide_start;input [31:0] n,d;input [4:0] target;begin
  div_num<=n;div_den<=d;div_rem<=0;div_quot<=0;div_count<=0;
  div_return<=target;state<=DIVIDE;
 end endtask
 task reject;input [7:0] code;begin
  error<=1;error_code<=code;state<=FAILED;pixel_valid<=0;
 end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=HEAD;div_return<=0;pos<=0;bf_size<=0;offset<=0;dib<=0;width<=0;height<=0;
   compression<=0;size_latched<=0;magic<=0;planes<=0;bits<=0;top_down<=0;
   fit_width_limited<=0;input_ended<=0;row_bytes<=0;row_stride<=0;row_byte<=0;
   required_size<=0;size_rows<=0;loaded_rows<=0;load_row<=0;load_x<=0;phase<=0;b<=0;g<=0;
   ox<=0;oy<=0;dx<=0;dy<=0;pad_x<=0;pad_y<=0;x_step<=0;y_step<=0;x_coord<=0;y_coord<=0;
   div_num<=0;div_den<=0;div_quot<=0;div_rem<=0;div_count<=0;
   read_x<=0;p00<=0;p01<=0;p10<=0;p11<=0;rendered<=0;channel<=0;lerp_stage<=0;
   h0<=0;h1<=0;lerp_base<=0;lerp_delta<=0;lerp_weight<=0;lerp_product<=0;
   pixel_valid<=0;pixel_rgb<=0;pixel_offset<=0;pixel_last<=0;done<=0;error<=0;error_code<=0;
   checksum<=0;source_width<=0;source_height<=0;scaled_width<=0;scaled_height<=0;
  end else if(begin_file)begin
   state<=HEAD;pos<=0;bf_size<=0;offset<=0;dib<=0;width<=0;height<=0;compression<=0;
   size_latched<=file_size;magic<=0;planes<=0;bits<=0;input_ended<=0;phase<=0;
   loaded_rows<=0;load_row<=0;load_x<=0;row_byte<=0;ox<=0;oy<=0;dx<=0;dy<=0;
   x_coord<=0;y_coord<=0;pixel_valid<=0;pixel_last<=0;done<=0;error<=0;error_code<=0;
   checksum<=0;source_width<=0;source_height<=0;scaled_width<=0;scaled_height<=0;
  end else begin
   if(pixel_valid&&pixel_ready)begin pixel_valid<=0;checksum<=checksum+{8'b0,pixel_rgb};end
   case(state)
    HEAD:if(pos==54)state<=CHECK;
    CHECK:if(!base_header_ok)reject(8'h21);else begin
     source_width<=width[10:0];source_height<=abs_height[9:0];top_down<=height[31];
     row_bytes<=header_row_bytes[11:0];row_stride<=header_stride[11:0];
     required_size<=offset;size_rows<=0;state<=SIZE;
    end
    SIZE:if(size_rows<source_height)begin required_size<=required_size+row_stride;size_rows<=size_rows+1'b1;end
     else if(required_size>bf_size||required_size>size_latched)reject(8'h21);
     else state<=FIT;
    FIT:if(times_height(source_width)>=times_width({1'b0,source_height}))begin
     scaled_width<=WIDTH;fit_width_limited<=1;divide_start(times_width({1'b0,source_height}),source_width,FIT_RESULT);
    end else begin scaled_height<=HEIGHT;fit_width_limited<=0;divide_start(times_height(source_width),source_height,FIT_RESULT);end
    FIT_RESULT:begin
     if(fit_width_limited)scaled_height<=div_quot==0?1:div_quot[9:0];
     else scaled_width<=div_quot==0?1:div_quot[10:0];state<=X_STEP;
    end
    X_STEP:begin
     pad_x<=(WIDTH-scaled_width)>>1;
     pad_y<=top_down?((HEIGHT-scaled_height)>>1):((HEIGHT-scaled_height+1)>>1);
     divide_start((source_width-1'b1)<<12,scaled_width>1?scaled_width-1'b1:1,X_RESULT);
    end
    X_RESULT:begin x_step<=scaled_width>1?div_quot:0;state<=Y_STEP;end
    Y_STEP:divide_start((source_height-1'b1)<<12,scaled_height>1?scaled_height-1'b1:1,Y_RESULT);
    Y_RESULT:begin y_step<=scaled_height>1?div_quot:0;state<=ROW;end
    DIVIDE:begin
     div_num<={div_num[30:0],1'b0};div_quot<=div_next_quot;
     div_rem<=div_ge?div_trial-{1'b0,div_den}:div_trial;
     if(div_count==31)state<=div_return;else div_count<=div_count+1'b1;
    end
    ROW:if(active_row&&loaded_rows<=sy1)state<=READ;else state<=EMIT;
    READ:if(taking)begin
     if(pos>=offset)begin
      if(row_byte<row_bytes)case(phase)
       0:begin b<=in_byte;phase<=1;end
       1:begin g<=in_byte;phase<=2;end
       2:begin phase<=0;load_x<=load_x+1'b1;end
      endcase
      if(row_byte==row_stride-1'b1)begin
       row_byte<=0;load_x<=0;phase<=0;load_row<=load_row+1'b1;
       loaded_rows<=loaded_rows+1'b1;state<=ROW;
      end else row_byte<=row_byte+1'b1;
     end
    end
    EMIT:if(!active_row||!active_col)begin rendered<=0;state<=OUTPUT_PIXEL;end
     else begin read_x<=sx;state<=FETCH0;end
    FETCH0:state<=FETCH1;
    FETCH1:begin
     p00<=sy[0]?row1_q:row0_q;p10<=sy1[0]?row1_q:row0_q;
     read_x<=sx1;state<=CAPTURE;
    end
    CAPTURE:begin state<=LERP_LOAD;channel<=0;lerp_stage<=0;end
    LERP_LOAD:begin
     if(lerp_stage==0)begin
      p01<=sy[0]?row1_q:row0_q;p11<=sy1[0]?row1_q:row0_q;
      lerp_base<=p00[channel*8+:8];
      lerp_delta<=$signed({1'b0,(sy[0]?row1_q[channel*8+:8]:row0_q[channel*8+:8])})-
                   $signed({1'b0,p00[channel*8+:8]});lerp_weight<=$signed({1'b0,fx});
     end else if(lerp_stage==1)begin
      lerp_base<=p10[channel*8+:8];lerp_delta<=$signed({1'b0,p11[channel*8+:8]})-
       $signed({1'b0,p10[channel*8+:8]});lerp_weight<=$signed({1'b0,fx});
     end else begin
      lerp_base<=h0;lerp_delta<=$signed({1'b0,h1})-$signed({1'b0,h0});lerp_weight<=$signed({1'b0,fy});
     end
     state<=LERP_MUL;
    end
    LERP_MUL:begin lerp_product<=lerp_delta*lerp_weight;state<=LERP_ADD;end
    LERP_ADD:begin
     if(lerp_stage==0)begin h0<=lerp_value;lerp_stage<=1;state<=LERP_LOAD;end
     else if(lerp_stage==1)begin h1<=lerp_value;lerp_stage<=2;state<=LERP_LOAD;end
     else begin
      rendered[channel*8+:8]<=lerp_value;
      if(channel==2)state<=OUTPUT_PIXEL;
      else begin channel<=channel+1'b1;lerp_stage<=0;state<=LERP_LOAD;end
     end
    end
    OUTPUT_PIXEL:if(can_put)begin
     pixel_valid<=1;pixel_rgb<=rendered;
     pixel_offset<=times_width(top_down?{1'b0,oy}:HEIGHT-1-oy)+ox;
     pixel_last<=oy==HEIGHT-1&&ox==WIDTH-1;
     if(active_col)begin dx<=dx+1'b1;x_coord<=x_coord+x_step;end
     if(ox==WIDTH-1)begin
      ox<=0;dx<=0;x_coord<=0;
      if(active_row)begin dy<=dy+1'b1;y_coord<=y_coord+y_step;end
      if(oy==HEIGHT-1)state<=DRAIN;
      else begin oy<=oy+1'b1;state<=ROW;end
     end else begin ox<=ox+1'b1;state<=EMIT;end
    end
    DRAIN:if(input_ended)begin done<=1;state<=FINISHED;end
    default:begin end
   endcase
   if(taking)begin
    pos<=pos+1'b1;
    if(state==HEAD)begin
     if(pos<2)magic[pos*8+:8]<=in_byte;
     if(pos>=2&&pos<6)bf_size[(pos-2)*8+:8]<=in_byte;
     if(pos>=10&&pos<14)offset[(pos-10)*8+:8]<=in_byte;
     if(pos>=14&&pos<18)dib[(pos-14)*8+:8]<=in_byte;
     if(pos>=18&&pos<22)width[(pos-18)*8+:8]<=in_byte;
     if(pos>=22&&pos<26)height[(pos-22)*8+:8]<=in_byte;
     if(pos>=26&&pos<28)planes[(pos-26)*8+:8]<=in_byte;
     if(pos>=28&&pos<30)bits[(pos-28)*8+:8]<=in_byte;
     if(pos>=30&&pos<34)compression[(pos-30)*8+:8]<=in_byte;
    end
    if(in_last)begin
     input_ended<=1;
     if(pos+1'b1!=size_latched||pos+1'b1<54)reject(8'h22);
    end
   end
  end
 end
endmodule
