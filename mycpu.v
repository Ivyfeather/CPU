module mycpu(
    input  [ 5:0] int,

    input         clk,
    input         resetn,

    //inst sram-like
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    input         inst_sram_addrok,
    input         inst_sram_dataok,

    // data sram-like
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    input         data_sram_addrok,
    input         data_sram_dataok,

    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);
reg         reset;
always @(posedge clk) reset <= ~resetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [`ES_RES          -1:0] es_res;
wire [`MS_RES          -1:0] ms_res;
wire [`WS_RES          -1:0] ws_res;
wire [6:0]                   wbexc;
wire [6:0]                   memexc;
wire [31:0]                  EPC;
wire                         wr_re;

parameter TLBNUM = 16;

// search port 0
wire [18:0]s0_vpn2;                // vaddr 31~13 bits 
wire s0_odd_page;                  // vaddr 12 bit
wire [7:0]s0_asid;                 // ASID             
wire s0_found;                    // CP0_Index highest bit
wire [$clog2(TLBNUM)-1:0] s0_index;// index
wire [19:0]s0_pfn;                 // pfn; use odd_page to choose between pfn0 and pfn1 in TLB-entry
wire [2:0]s0_c;
wire     s0_d;
wire     s0_v;

// search port 1
wire [18:0]s1_vpn2;
wire s1_odd_page;
wire [ 7:0]s1_asid;
wire s1_found;
wire [$clog2(TLBNUM)-1:0]s1_index;
wire [19:0]s1_pfn;
wire [ 2:0]s1_c;
wire s1_d;
wire s1_v;

//write port
wire we;
wire [$clog2(TLBNUM)-1:0]w_index;
wire [18:0]w_vpn2;
wire [ 7:0]w_asid;
wire w_g;

wire [19:0]w_pfn0;
wire [ 2:0]w_c0;
wire w_d0;
wire w_v0;

wire [19:0] w_pfn1;
wire [ 2:0] w_c1;
wire w_d1;
wire w_v1;

// read port
wire [$clog2(TLBNUM)-1:0] r_index;
wire [18:0] r_vpn2;
wire [ 7:0] r_asid;
wire r_g;

wire [19:0] r_pfn0;
wire [ 2:0] r_c0;
wire r_d0;
wire r_v0;

wire [19:0] r_pfn1;
wire [ 2:0] r_c1;
wire r_d1;
wire r_v1;


// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_req   (inst_sram_req   ),
    .inst_sram_wr    (inst_sram_wr    ),
    .inst_sram_size  (inst_sram_size  ),
    .inst_sram_addr  (inst_sram_addr  ),
    .inst_sram_wdata (inst_sram_wdata ),
    .inst_sram_rdata (inst_sram_rdata ),
    .inst_sram_addrok(inst_sram_addrok),
    .inst_sram_dataok(inst_sram_dataok),
    .wbexc           (wbexc),
    .wr_re           (wr_re),

    .s0_vpn2         (s0_vpn2),         // vaddr 31~13 bits 
    .s0_odd_page     (s0_odd_page),     // vaddr 12 bit
    .s0_asid         (s0_asid),         // ASID       
    .s0_found        (s0_found),        // CP0_Index highest bit
    .s0_index        (s0_index),        // index
    .s0_pfn          (s0_pfn),          // pfn, use odd_page to choose between pfn0 and pfn1 in TLB-entry
    .s0_c            (s0_c),
    .s0_d            (s0_d),
    .s0_v            (s0_v)
);
// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    .es_res         (es_res),
    .ms_res         (ms_res),
    .ws_res         (ws_res),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .wbexc          (wbexc),
    .EPC            (EPC),
    .wr_re1         (wr_re)
);
// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .es_res         (es_res),
    // data sram interface
    .data_sram_req   (data_sram_req   ),
    .data_sram_wr    (data_sram_wr    ),
    .data_sram_size  (data_sram_size  ),
    .data_sram_addr  (data_sram_addr  ),
    .data_sram_wdata (data_sram_wdata ),
    .data_sram_addrok(data_sram_addrok),
    .wbexc           (wbexc),
    .memexc          (memexc),

    .s1_vpn2         (s1_vpn2),         // vaddr 31~13 bits 
    .s1_odd_page     (s1_odd_page),     // vaddr 12 bit
    .s1_asid         (s1_asid),         // ASID       
    .s1_found        (s1_found),        // CP0_Index highest bit
    .s1_index        (s1_index),        // index
    .s1_pfn          (s1_pfn),          // pfn, use odd_page to choose between pfn0 and pfn1 in TLB-entry
    .s1_c            (s1_c),
    .s1_d            (s1_d),
    .s1_v            (s1_v)
);
// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    .ms_res         (ms_res),
    //from data-sram
    .data_sram_rdata (data_sram_rdata ),
    .data_sram_dataok(data_sram_dataok),
    .memexc(memexc),
    .wbexc(wbexc)
);
// WB stage
wb_stage wb_stage(
    .int            (int            ),
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .ws_res           (ws_res),
    //write port
    .we             (we),
    .w_index        (w_index),
    .w_vpn2         (w_vpn2),
    .w_asid         (w_asid),
    .w_g            (w_g),
    .w_pfn0         (w_pfn0),
    .w_c0           (w_c0),
    .w_d0           (w_d0),
    .w_v0           (w_v0),
    .w_pfn1         (w_pfn1),
    .w_c1           (w_c1),
    .w_d1           (w_d1),
    .w_v1           (w_v1),
    // read port
    .r_index        (r_index),
    .r_vpn2         (r_vpn2),
    .r_asid         (r_asid),
    .r_g            (r_g),
    .r_pfn0         (r_pfn0),
    .r_c0           (r_c0),
    .r_d0           (r_d0),
    .r_v0           (r_v0),
    .r_pfn1         (r_pfn1),
    .r_c1           (r_c1),
    .r_d1           (r_d1),
    .r_v1           (r_v1),

    //trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_wen  ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .exception(wbexc),
    .EPC(EPC)
);

// search 0 in IF, search 1 in EXE
// read and write in WB
tlb tlb(
// search port 0
    .s0_vpn2    (s0_vpn2),                // vaddr 31~13 bits 
    .s0_odd_page(s0_odd_page),            // vaddr 12 bit
    .s0_asid    (s0_asid),                // ASID             
    .s0_found   (s0_found),               // CP0_Index highest bit
    .s0_index   (s0_index),               // index
    .s0_pfn     (s0_pfn),                 // pfn, use odd_page to choose between pfn0 and pfn1 in TLB-entry
    .s0_c       (s0_c),
    .s0_d       (s0_d),
    .s0_v       (s0_v),

// search port 1
    .s1_vpn2    (s1_vpn2),
    .s1_odd_page(s1_odd_page),
    .s1_asid    (s1_asid),
    .s1_found   (s1_found),
    .s1_index   (s1_index),
    .s1_pfn     (s1_pfn),
    .s1_c       (s1_c),
    .s1_d       (s1_d),
    .s1_v       (s1_v),

//write port
    .we         (we),
    .w_index    (w_index),
    .w_vpn2     (w_vpn2),
    .w_asid     (w_asid),
    .w_g        (w_g),

    .w_pfn0     (w_pfn0),
    .w_c0       (w_c0),
    .w_d0       (w_d0),
    .w_v0       (w_v0),

    .w_pfn1     (w_pfn1),
    .w_c1       (w_c1),
    .w_d1       (w_d1),
    .w_v1       (w_v1),

 // read port
    .r_index    (r_index),
    .r_vpn2     (r_vpn2),
    .r_asid     (r_asid),    
    .r_g        (r_g),

    .r_pfn0     (r_pfn0),
    .r_c0       (r_c0),
    .r_d0       (r_d0),
    .r_v0       (r_v0),

    .r_pfn1     (r_pfn1),
    .r_c1       (r_c1),
    .r_d1       (r_d1),
    .r_v1       (r_v1)
);

endmodule
