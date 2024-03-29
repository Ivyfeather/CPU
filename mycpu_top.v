module mycpu_top(
    input  [ 5:0] int,

    input         aclk,
    input         aresetn,
    //axi
    //ar
    output [3:0] arid      ,
    output [31:0] araddr   ,
    output [7:0] arlen     ,
    output [2:0] arsize    ,
    output [1:0] arburst   ,
    output [1:0] arlock    ,
    output [3:0] arcache   ,
    output [2:0] arprot    ,
    output arvalid  ,
    input arready   ,    
    //r              
    input rid       ,
    input [31:0] rdata    ,
    input [1:0] rresp     ,
    input rlast     ,
    input rvalid    ,
    output rready   ,
    //aw           
    output [3:0] awid      ,
    output [31:0] awaddr   ,
    output [7:0] awlen     ,
    output [2:0] awsize    ,
    output [1:0] awburst   ,
    output [1:0] awlock    ,
    output [3:0] awcache   ,
    output [2:0] awprot    ,
    output awvalid  ,
    input awready   ,
    //w          
    output [3:0] wid       ,
    output [31:0] wdata    ,
    output [3:0] wstrb     ,
    output wlast    ,
    output wvalid   ,
    input wready    ,
    //b              
    input [3:0] bid       ,
    input [1:0] bresp     ,
    input bvalid     ,
    output bready    ,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);
//cpu inst sram-like
wire        cpu_inst_req;
wire        cpu_inst_wr;
wire [ 1:0] cpu_inst_size;
wire [31:0] cpu_inst_addr;
wire [31:0] cpu_inst_wdata;
wire [31:0] cpu_inst_rdata;
wire        cpu_inst_addr_ok;
wire        cpu_inst_data_ok;

//cpu data sram-like
wire        cpu_data_req;
wire        cpu_data_wr;
wire [ 1:0] cpu_data_size;
wire [31:0] cpu_data_addr;
wire [31:0] cpu_data_wdata;
wire [31:0] cpu_data_rdata;
wire        cpu_data_addr_ok;
wire        cpu_data_data_ok;

mycpu cpu(
    .int              ( int              ),

    .clk              ( aclk             ),
    .resetn           ( aresetn          ),

    //inst sram-like
    .inst_sram_req    ( cpu_inst_req     ),
    .inst_sram_wr     ( cpu_inst_wr      ),
    .inst_sram_size   ( cpu_inst_size    ),
    .inst_sram_addr   ( cpu_inst_addr    ),
    .inst_sram_wdata  ( cpu_inst_wdata   ),
    .inst_sram_rdata  ( cpu_inst_rdata   ),
    .inst_sram_addrok ( cpu_inst_addr_ok ),
    .inst_sram_dataok ( cpu_inst_data_ok ),

    //data sram-like
    .data_sram_req    ( cpu_data_req     ),
    .data_sram_wr     ( cpu_data_wr      ),
    .data_sram_size   ( cpu_data_size    ),
    .data_sram_addr   ( cpu_data_addr    ),
    .data_sram_wdata  ( cpu_data_wdata   ),
    .data_sram_rdata  ( cpu_data_rdata   ),
    .data_sram_addrok ( cpu_data_addr_ok ),
    .data_sram_dataok ( cpu_data_data_ok ),

    //debug interface
    .debug_wb_pc      ( debug_wb_pc      ),
    .debug_wb_rf_wen  ( debug_wb_rf_wen  ),
    .debug_wb_rf_wnum ( debug_wb_rf_wnum ),
    .debug_wb_rf_wdata( debug_wb_rf_wdata)
);

cpu_axi_interface bridge(
    .clk           ( aclk          ),
    .resetn        ( aresetn       ),

    //inst sram-like 
    .inst_req      ( cpu_inst_req     ),
    .inst_wr       ( cpu_inst_wr      ),
    .inst_size     ( cpu_inst_size    ),
    .inst_addr     ( cpu_inst_addr    ),
    .inst_wdata    ( cpu_inst_wdata   ),
    .inst_rdata    ( cpu_inst_rdata   ),
    .inst_addr_ok  ( cpu_inst_addr_ok ),
    .inst_data_ok  ( cpu_inst_data_ok ),
    
    //data sram-like 
    .data_req      ( cpu_data_req     ),
    .data_wr       ( cpu_data_wr      ),
    .data_size     ( cpu_data_size    ),
    .data_addr     ( cpu_data_addr    ),
    .data_wdata    ( cpu_data_wdata   ),
    .data_rdata    ( cpu_data_rdata   ),
    .data_addr_ok  ( cpu_data_addr_ok ),
    .data_data_ok  ( cpu_data_data_ok ),

    //axi
    //ar
    .arid      ( arid         ),
    .araddr    ( araddr       ),
    .arlen     ( arlen        ),
    .arsize    ( arsize       ),
    .arburst   ( arburst      ),
    .arlock    ( arlock       ),
    .arcache   ( arcache      ),
    .arprot    ( arprot       ),
    .arvalid   ( arvalid      ),
    .arready   ( arready      ),
    //r              
    .rid       ( rid          ),
    .rdata     ( rdata        ),
    .rresp     ( rresp        ),
    .rlast     ( rlast        ),
    .rvalid    ( rvalid       ),
    .rready    ( rready       ),
    //aw           
    .awid      ( awid         ),
    .awaddr    ( awaddr       ),
    .awlen     ( awlen        ),
    .awsize    ( awsize       ),
    .awburst   ( awburst      ),
    .awlock    ( awlock       ),
    .awcache   ( awcache      ),
    .awprot    ( awprot       ),
    .awvalid   ( awvalid      ),
    .awready   ( awready      ),
    //w          
    .wid       ( wid          ),
    .wdata     ( wdata        ),
    .wstrb     ( wstrb        ),
    .wlast     ( wlast        ),
    .wvalid    ( wvalid       ),
    .wready    ( wready       ),
    //b              
    .bid       ( bid          ),
    .bresp     ( bresp        ),
    .bvalid    ( bvalid       ),
    .bready    ( bready       )
);

endmodule
