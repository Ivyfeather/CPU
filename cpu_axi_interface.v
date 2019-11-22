`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2019/11/11 21:09:35
// Design Name: 
// Module Name: bridge
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define read_init 1
`define read_data 2
`define read_inst 3
`define read_ready 4
`define read_complete 5
`define write_init 6
`define write_acaddr 7
`define write_ready 8
`define write_complete 9
`define write_acdata 10


module cpu_axi_interface(
    input clk           ,
    input resetn        ,

    //inst sram-like 
    input inst_req      ,
    input inst_wr       ,
    input [1:0] inst_size     ,
    input [31:0] inst_addr     ,
    input [31:0] inst_wdata    ,
    output [31:0]inst_rdata    ,
    output inst_addr_ok  ,
    output inst_data_ok  ,
    
    //data sram-like 
    input data_req      ,
    input data_wr       ,
    input [1:0] data_size     ,
    input [31:0] data_addr     ,
    input [31:0] data_wdata    ,
    output[31:0] data_rdata    ,
    output data_addr_ok  ,
    output data_data_ok  ,

    //axi
    //ar
    output [3:0] arid      ,
    output [31:0] araddr    ,
    output [7:0] arlen     ,
    output [2:0] arsize    ,
    output [1:0] arburst   ,
    output [1:0] arlock    ,
    output [3:0] arcache   ,
    output [2:0] arprot    ,
    output arvalid   ,
    input arready   ,
    //r              
    input rid       ,
    input [31:0] rdata     ,
    input [1:0] rresp     ,
    input rlast     ,
    input rvalid    ,
    output rready    ,
    //aw           
    output [3:0] awid      ,
    output [31:0] awaddr    ,
    output [7:0] awlen     ,
    output [2:0] awsize    ,
    output [1:0] awburst   ,
    output [1:0] awlock    ,
    output [3:0] awcache   ,
    output [2:0] awprot    ,
    output awvalid   ,
    input awready   ,
    //w          
    output [3:0] wid       ,
    output [31:0] wdata     ,
    output [3:0] wstrb     ,
    output wlast     ,
    output wvalid    ,
    input wready    ,
    //b              
    input [3:0] bid       ,
    input [1:0] bresp     ,
    input bvalid     ,
    output bready
);
reg [3:0] rdstate;
reg [3:0] wrstate;
wire [3:0] rdnext;
wire [3:0] wrnext;
reg sign;	// means whether or not there is an unfinished read_op 
// 用于判断写请求前是否有读操作 //used to judge whether a read_op occurs before write_req
always @(posedge clk)
begin
   if(!resetn)
     rdstate <= `read_init;
   else
     rdstate <= rdnext;
end
always @(posedge clk)
begin
   if(!resetn)
     wrstate <= `write_init;
   else
     wrstate <= wrnext;
end
assign rdnext=(rdstate == `read_init && data_req && data_wr == 0 && wrstate == `write_init)?`read_data:
              (rdstate == `read_init && inst_req && inst_wr == 0)?`read_inst:
              (rdstate == `read_data && arready)?`read_ready:
              (rdstate == `read_inst && arready)?`read_ready:
              (rdstate == `read_ready && rvalid)?`read_complete:
              (rdstate == `read_complete)?`read_init:
              rdstate;
assign wrnext=(wrstate == `write_init && data_req && data_wr == 1 && sign == 0)?`write_acaddr:
              (wrstate == `write_acaddr && awready)?`write_acdata:
              (wrstate == `write_acdata && wready)?`write_ready:
              (wrstate == `write_ready && bvalid == 1)?`write_complete:
              (wrstate == `write_complete)?`write_init:
              wrstate;
reg [31:0]inst_addr_r;
reg [31:0]data_addr_r;
reg [31:0]wdata_r;
reg [2:0] inst_arsize_r;
reg [2:0] data_arsize_r;
reg [2:0] awsize_r;
always @(posedge clk)
begin
    if(!resetn)
    begin
      inst_addr_r <= 0;
      inst_arsize_r <= 0;
    end
    else if(rdstate == `read_init)
    begin
      inst_addr_r <= inst_addr;
      inst_arsize_r <= inst_size;
    end   
end
always @(posedge clk)
begin
    if(!resetn)
    begin
      data_addr_r <= 0;
      data_arsize_r <= 0;
      awsize_r <= 0;
      wdata_r <= 0;
    end
    else if(rdnext == `read_data || wrnext == `write_acaddr)
    begin
      data_addr_r <= data_addr;
      data_arsize_r <= data_size;
      awsize_r <= data_size;
      wdata_r <= data_wdata;
    end
end
assign arid = (rdstate == `read_data)?1: 
            0;
assign araddr = (rdstate == `read_data)?data_addr_r:
              inst_addr_r;
assign arsize = (rdstate == `read_data)?data_arsize_r:
              inst_arsize_r;
assign arvalid = (rdstate == `read_data || rdstate == `read_inst);
reg [31:0] rdata_r;
reg rid_r;
always @(posedge clk)
begin
   if(!resetn)
   begin
     rdata_r <= 0;
     rid_r 	 <= 0;
   end
   else if(rdnext == `read_complete)
   begin
     rdata_r <= rdata;
     rid_r 	 <= rid;
   end
end
always @(posedge clk)
begin
   if(!resetn)
      sign <= 0;
   else if(rdnext == `read_data)
      sign <= 1;
   else if(rvalid)
      sign <= 0;
end
assign awaddr = {data_addr_r[31:2], 2'b00};
assign awsize = awsize_r;
assign awvalid = (wrstate == `write_acaddr);
assign wdata = wdata_r;
assign wvalid = (wrstate == `write_acaddr || wrstate == `write_acdata); //because we have already received wdata in write_acaddr alongwith waddr
assign bready = (wrstate == `write_ready);
assign inst_addr_ok = (rdstate == `read_init && (data_wr == 1 || data_req == 0)); // can execute an inst_read during a data_write operation
assign inst_data_ok = (rdstate == `read_complete && rid_r == 0);
assign inst_rdata = rdata_r;
assign data_addr_ok = (rdnext == `read_data || wrnext == `write_acaddr);
assign data_data_ok = (rdstate == `read_complete && rid_r == 1) || wrstate == `write_complete;
assign rready = (rdstate == `read_ready);
assign data_rdata = rdata_r;

// fixed signal in this experiment
assign arlen = 0;
assign arburst = 2'b01;
assign arlock = 0;
assign arcache = 0;
assign arprot = 0;
assign awid = 1;
assign awlen = 0;
assign awburst = 2'b01;
assign awlock = 0;
assign awcache = 0;
assign awprot = 0;
assign wid = 1;
assign wlast = 1;

assign wstrb=(data_addr_r[1:0] == 3 && awsize_r == 0)?4'b1000: //sb
             (data_addr_r[1:0] == 2 && awsize_r == 0)?4'b0100: //sb
             (data_addr_r[1:0] == 1 && awsize_r == 0)?4'b0010: //sb
             (data_addr_r[1:0] == 0 && awsize_r == 0)?4'b0001: //sb
             (data_addr_r[1:0] == 2 && awsize_r == 1)?4'b1100: //sh
             (data_addr_r[1:0] == 0 && awsize_r == 1)?4'b0011: //sh
             (data_addr_r[1:0] == 1 && awsize_r == 1)?4'b0001: //swl
             (data_addr_r[1:0] == 2 && awsize_r == 2)?4'b0011: //swl
             (data_addr_r[1:0] == 3 && awsize_r == 2)?4'b0111: //swl
             (data_addr_r[1:0] == 0 && awsize_r == 2)?4'b1111: //swr
             (data_addr_r[1:0] == 1 && awsize_r == 2)?4'b1110: //swr
             (data_addr_r[1:0] == 2 && awsize_r == 1)?4'b1100: //swr
             (data_addr_r[1:0] == 3 && awsize_r == 0)?4'b1000: //swr
             4'b1111;										   //sw
endmodule
