`timescale 1ns/1ps
module tb_color_adjust;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,de=0,bypass=0;
 reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=0;
 reg signed [8:0] brightness=0;reg [9:0] contrast=256;reg [4:0] alpha=16;
 wire out_de;wire [10:0] out_x;wire [9:0] out_y;wire [23:0] out_rgb;
 color_adjust dut(clk,rst,de,x,y,rgb,brightness,contrast,bypass,alpha,out_de,out_x,out_y,out_rgb);
 reg [45:0] expected[0:2];
 integer frame_br=0,frame_co=256,frame_alpha=16;
 reg frame_bypass=0;
 integer checks=0,i;
 function [7:0] reference_channel(input integer channel,input integer br,input integer co,input integer fade,input bit bp);
  integer adjusted;
  begin
   adjusted=bp?channel:(((channel-128)*co)>>>8)+128+br;
   if(adjusted<0)adjusted=0;if(adjusted>255)adjusted=255;
   reference_channel=(adjusted*fade)>>4;
  end
 endfunction
 function [23:0] reference_rgb(input [23:0] pixel);
  begin reference_rgb={reference_channel(pixel[23:16],frame_br,frame_co,frame_alpha,frame_bypass),
   reference_channel(pixel[15:8],frame_br,frame_co,frame_alpha,frame_bypass),
   reference_channel(pixel[7:0],frame_br,frame_co,frame_alpha,frame_bypass)};end
 endfunction
 always @(posedge clk)begin
  if(rst)begin
   expected[0]=0;expected[1]=0;expected[2]=0;
   frame_br=0;frame_co=256;frame_alpha=16;frame_bypass=0;
  end else begin
   if(de&&x==0&&y==0)begin
    frame_br=$signed(brightness);frame_co=contrast;frame_alpha=alpha;frame_bypass=bypass;
   end
   expected[2]=expected[1];expected[1]=expected[0];
   expected[0]={de,x,y,reference_rgb(rgb)};
  end
  #1;
  // The reset bubbles have de=0; their intermediate RGB has no meaning.
  // Once three real inputs have traversed the pipeline, compare blanking
  // pixels too, so a de/x/y alignment error cannot hide behind this rule.
  if(checks>=2&&{out_de,out_x,out_y,out_rgb}!==expected[2])
   $fatal(1,"global adjustment/fade/metadata mismatch got=%h expected=%h",{out_de,out_x,out_y,out_rgb},expected[2]);
  if(!rst)checks=checks+1;
 end
 task drive(input bit active,input integer px,input integer py,input [23:0] pixel,
  input integer br,input integer co,input integer fade,input bit bp);
  begin @(negedge clk);de=active;x=px;y=py;rgb=pixel;brightness=br;contrast=co;alpha=fade;bypass=bp;end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  // Identity; first pixel takes the new settings immediately.
  drive(1,0,0,24'h0080ff,0,256,16,0);
  // All following register changes must wait for the next frame boundary.
  drive(1,1,0,24'h01ff7f,127,768,0,1);
  drive(0,640,480,24'h123456,-128,0,1,0);
  for(i=0;i<100;i=i+1)
   drive(i%4!=0,1+i,i%480,$random,-128+(i%256),i%769,i%17,i%2);
  drive(1,0,0,24'h0080ff,-128,768,16,0);
  drive(1,1,0,24'hff8000,127,0,16,1);
  drive(1,2,0,24'h7f8182,0,256,16,0);
  drive(1,0,0,24'h007fff,127,768,8,0);
  for(i=0;i<80;i=i+1)drive(1,1+i,3,$random,-128,0,0,1);
  // Bypass prevents a repeated adjustment in dedicated BRIGHT/CONTRAST
  // filter modes, while fade is still applied exactly once afterwards.
  drive(1,0,0,24'hff8001,-128,768,4,1);
  for(i=0;i<80;i=i+1)drive(i%3!=0,1+i,7,$random,0,256,16,0);
  drive(1,0,0,24'hffffff,127,0,0,0);
  drive(1,1,0,24'h0080ff,0,256,16,0);
  drive(1,0,0,24'hfefdfc,0,256,16,0);
  for(i=0;i<80;i=i+1)drive(1,1+i,13,$random,127,768,8,1);
  repeat(5)@(negedge clk);
  if(checks<300)$fatal(1,"insufficient streamed pixels");
  $display("TEST PASS color_adjust: %d streamed pixels, frame latching, signed saturation, bypass, fade order and raster alignment",checks);
  $finish;
 end
endmodule
