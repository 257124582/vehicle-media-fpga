`timescale 1ns/1ps
// Simulation only. The TD primitive is a black box; APUG011 supplies this bus model.
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,
 input [1:0] ba,inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 IS42s32200 model(.Clk(clk),.Cke(cke),.Cs_n(cs_n),.Ras_n(ras_n),.Cas_n(cas_n),
  .We_n(we_n),.Ba(ba),.Addr(addr),.Dqm({dm3,dm2,dm1,dm0}),.Dq(dq));
endmodule
