`include "mycpu.h"

module id_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          es_allowin    ,
    input   [`ES_RES         -1:0] es_res        ,
    input   [`MS_RES         -1:0] ms_res        ,
    input   [`WS_RES         -1:0] ws_res        ,
    input   [6:0]                  wbexc         ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus,
    input  [31:0]                  EPC
);

reg         ds_valid   ;
wire        ds_ready_go;

wire [31                 :0] fs_pc;
reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;
assign fs_pc = fs_to_ds_bus[31:0];

wire [31:0] ds_inst;
wire [31:0] ds_pc  ;
wire [ 6:0]  fromexception;
wire [ 6:0]  toexception;
wire [31:0]  bad_pc;
assign {bad_pc,
        fromexception,
        ds_inst,
        ds_pc  } = fs_to_ds_bus_r;

wire [ 3:0] rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
assign {rf_we   ,  //40:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;

wire        br_taken;
wire [31:0] br_target;

wire [15:0] alu_op;
wire        load_op;
wire        store_op;
wire        src1_is_sa;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_8;
wire        res_from_mem;
wire [ 3:0] gr_we;
wire        mem_we;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] rs_value;
wire [31:0] rt_value;

wire [ 5:0] op;
wire [ 4:0] rs;
wire [ 4:0] rt;
wire [ 4:0] rd;
wire [ 4:0] sa;
wire [ 5:0] func;
wire [25:0] jidx;
wire [63:0] op_d;
wire [31:0] rs_d;
wire [31:0] rt_d;
wire [31:0] rd_d;
wire [31:0] sa_d;
wire [63:0] func_d;
wire dst_is_rs;

wire        inst_addu;
wire        inst_subu;
wire        inst_slt;
wire        inst_sltu;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_nor;
wire        inst_sll;
wire        inst_srl;
wire        inst_sra;
wire        inst_addiu;
wire        inst_lui;
wire        inst_lw;
wire        inst_sw;
wire        inst_beq;
wire        inst_bne;
wire        inst_jal;
wire        inst_jr;
// lab 6
wire        inst_add;
wire        inst_addi;
wire        inst_sub;
wire        inst_slti;
wire        inst_sltiu;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sllv;
wire        inst_srav;
wire        inst_srlv;
wire        inst_mult;
wire        inst_multu;
wire        inst_div;
wire        inst_divu;
wire        inst_mfhi;
wire        inst_mflo;
wire        inst_mthi;
wire        inst_mtlo;
//lab 7
wire        inst_lb;
wire        inst_lbu;
wire        inst_lh;
wire        inst_lhu;
wire        inst_lwl;
wire        inst_lwr;
wire        inst_sb;
wire        inst_sh;
wire        inst_swl;
wire        inst_swr;

wire        inst_bgez;
wire        inst_bgtz;
wire        inst_blez;
wire        inst_bltz;
wire        inst_bltzal;
wire        inst_bgezal;
wire        inst_j;
wire        inst_jalr;
wire        inst_eret;
wire        inst_mtc0;
wire        inst_mfc0;
wire        inst_syscall;
wire        inst_break;


wire        dst_is_r31;  
wire        dst_is_rt;   
wire        iszero;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rs_eq_rt;
wire        wr_re;
wire [41:0] cp0_msg;
wire [ 6:0] memop_type;

assign br_bus       = {eret, br_taken, br_target};
assign load_op      = inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr | inst_mfc0;
assign store_op     = inst_sw | inst_sb | inst_sh | inst_swl | inst_swr; 

//******* handling exception *******
wire syscall;
wire address_error_read;
wire address_error_write;
wire integer_overflow;
wire breakpoint;
wire reserved_instruction;
wire interrupt;
wire [ 6:0] exception;
assign exception = {  interrupt,            //6:6
                      reserved_instruction, //5:5
                      breakpoint,           //4:4
                      integer_overflow,     //3:3
                      address_error_write,  //2:2
                      address_error_read,   //1:1
                      syscall               //0:0
                    };

assign syscall              = inst_syscall;
assign address_error_read   = 0;
assign address_error_write  = 0;
assign integer_overflow     = inst_add | inst_addi | inst_sub;
assign breakpoint           = inst_break;
//assign reserved_instruction; see line 384
//assign interrupt; see ws_res
assign toexception  = exception | fromexception; 

reg at_delay_slot;
always @(posedge clk) begin
  if (reset) 
    at_delay_slot <= 1'b0;
  else if (branch_op || jump_op)
    at_delay_slot <= 1'b1; 
  else 
    at_delay_slot <= 1'b0;
end

// TEST FOR GIT
//======= handling exception =======

assign ds_to_es_bus = (ds_ready_go==1'b0)?280'b0:
                      {bad_pc       , //279:248       
                       at_delay_slot, //247:247
                       cp0_msg     ,  //246:205
                       toexception ,  //204:198
                       memop_type  ,  //197:191
                       ds_inst     ,  //190:159     
                       alu_op      ,  //158:143
                       load_op     ,  //142:142
                       src1_is_sa  ,  //141:141
                       src1_is_pc  ,  //140:140
                       src2_is_imm ,  //139:139
                       src2_is_8   ,  //138:138
                       gr_we       ,  //137:134
                       mem_we      ,  //133:133
                       dest        ,  //132:128
                       imm         ,  //127:96
                       rs_value    ,  //95 :64
                       rt_value    ,  //63 :32
                       ds_pc          //31 :0
                      };
reg eret;
always@(posedge clk)
begin
   if(inst_eret)
      eret <= 1;
   else
      eret <= 0;
end
assign ds_allowin     = (inst_eret)? 0:
                        !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = (ds_valid && ds_ready_go)||(wr_re);
always @(posedge clk) begin
    if(reset)
        fs_to_ds_bus_r <=32'h0;
    else if(wbexc || inst_eret || eret)
        fs_to_ds_bus_r <=32'h0;
    else if (fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end
always @(posedge clk) begin
    if (reset) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end
end

assign op   = ds_inst[31:26];
assign rs   = ds_inst[25:21];
assign rt   = ds_inst[20:16];
assign rd   = ds_inst[15:11];
assign sa   = ds_inst[10: 6];
assign func = ds_inst[ 5: 0];
assign imm  = (inst_andi | inst_ori | inst_xori)? {16'h0000,ds_inst[15:0]}:
                                                  {{16{ds_inst[15]}}, ds_inst[15: 0]};
assign jidx = ds_inst[25: 0];

decoder_6_64 u_dec0(.in(op  ), .out(op_d  ));
decoder_6_64 u_dec1(.in(func), .out(func_d));
decoder_5_32 u_dec2(.in(rs  ), .out(rs_d  ));
decoder_5_32 u_dec3(.in(rt  ), .out(rt_d  ));
decoder_5_32 u_dec4(.in(rd  ), .out(rd_d  ));
decoder_5_32 u_dec5(.in(sa  ), .out(sa_d  ));

assign inst_addu   = op_d[6'h00] & func_d[6'h21] & sa_d[5'h00];
assign inst_subu   = op_d[6'h00] & func_d[6'h23] & sa_d[5'h00];
assign inst_slt    = op_d[6'h00] & func_d[6'h2a] & sa_d[5'h00];
assign inst_sltu   = op_d[6'h00] & func_d[6'h2b] & sa_d[5'h00];
assign inst_and    = op_d[6'h00] & func_d[6'h24] & sa_d[5'h00];
assign inst_or     = op_d[6'h00] & func_d[6'h25] & sa_d[5'h00];
assign inst_xor    = op_d[6'h00] & func_d[6'h26] & sa_d[5'h00];
assign inst_nor    = op_d[6'h00] & func_d[6'h27] & sa_d[5'h00];
assign inst_sll    = op_d[6'h00] & func_d[6'h00] & rs_d[5'h00];
assign inst_srl    = op_d[6'h00] & func_d[6'h02] & rs_d[5'h00];
assign inst_sra    = op_d[6'h00] & func_d[6'h03] & rs_d[5'h00];
assign inst_addiu  = op_d[6'h09];
assign inst_lui    = op_d[6'h0f] & rs_d[5'h00];
assign inst_lw     = op_d[6'h23];
assign inst_sw     = op_d[6'h2b];
assign inst_beq    = op_d[6'h04];
assign inst_bne    = op_d[6'h05];
assign inst_jal    = op_d[6'h03];
assign inst_jr     = op_d[6'h00] & func_d[6'h08] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];
// lab 6
assign inst_add    = op_d[6'h00] & func_d[6'h20] & sa_d[5'h0];
assign inst_addi   = op_d[6'h08];
assign inst_sub    = op_d[6'h00] & func_d[6'h22] & sa_d[5'h00];
assign inst_slti   = op_d[6'h0a];
assign inst_sltiu  = op_d[6'h0b];
assign inst_andi   = op_d[6'h0c];
assign inst_ori    = op_d[6'h0d];
assign inst_xori   = op_d[6'h0e];
assign inst_sllv   = op_d[6'h00] & func_d[6'h04] & sa_d[5'h00];
assign inst_srav   = op_d[6'h00] & func_d[6'h07] & sa_d[5'h00];
assign inst_srlv   = op_d[6'h00] & func_d[6'h06] & sa_d[5'h00];
assign inst_mult   = op_d[6'h00] & func_d[6'h18] & sa_d[5'h00]&rd_d[5'h00];
assign inst_multu  = op_d[6'h00] & func_d[6'h19] & sa_d[5'h00]&rd_d[5'h00];
assign inst_div    = op_d[6'h00] & func_d[6'h1a] & sa_d[5'h00]&rd_d[5'h00];
assign inst_divu   = op_d[6'h00] & func_d[6'h1b] & sa_d[5'h00]&rd_d[5'h00];
assign inst_mfhi   = op_d[6'h00] & rs_d[5'h00] & rt_d[5'h00] & sa_d[5'h00] & func_d[6'h10];
assign inst_mflo   = op_d[6'h00] & rs_d[5'h00] & rt_d[5'h00] & sa_d[5'h00] & func_d[6'h12];
assign inst_mthi   = op_d[6'h00] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00] & func_d[6'h11];
assign inst_mtlo   = op_d[6'h00] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00] & func_d[6'h13];
//lab 7
assign inst_lb     = op_d[6'h20];
assign inst_lbu    = op_d[6'h24];
assign inst_lh     = op_d[6'h21];
assign inst_lhu    = op_d[6'h25];
assign inst_lwl    = op_d[6'h22];
assign inst_lwr    = op_d[6'h26];
assign inst_sb     = op_d[6'h28];
assign inst_sh     = op_d[6'h29];
assign inst_swl    = op_d[6'h2a];
assign inst_swr    = op_d[6'h2e];
assign inst_bgez   = op_d[6'h01] & rt_d[5'h01];
assign inst_bgtz   = op_d[6'h07];
assign inst_blez   = op_d[6'h06];
assign inst_bltz   = op_d[6'h01] & rt_d[5'h00];
assign inst_bgezal = op_d[6'h01] & rt_d[5'h11];
assign inst_bltzal = op_d[6'h01] & rt_d[5'h10];
assign inst_j      = op_d[6'h02];
assign inst_jalr   = op_d[6'h00] & rt_d[5'h00] & sa_d[5'h00] & func_d[6'h09];
//lab 8 & 9
assign inst_eret   = op_d[6'h10] & rs_d[5'h10] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00] &func_d[6'h18];
assign inst_mfc0   = op_d[6'h10] & rs_d[5'h00] & sa_d[5'h00];
assign inst_mtc0   = op_d[6'h10] & rs_d[5'h04] & sa_d[5'h00];
assign inst_syscall= op_d[6'h00] & func_d[6'h0c];
assign inst_break  = op_d[6'h00] & func_d[6'h0d];
// cp0 related info
assign cp0_msg[41:40] = (inst_mtc0)? 2'b01 :
                        (inst_mfc0)? 2'b10 :
                        (inst_eret)? 2'b11 : 0;
assign cp0_msg[39:37] = ds_inst[2:0];
assign cp0_msg[36:32] = ds_inst[15:11];
assign cp0_msg[31:0] = rt_value;
// memory related info
assign memop_type[0] = inst_lw | inst_sw;
assign memop_type[1] = inst_lb | inst_sb;
assign memop_type[2] = inst_lbu;
assign memop_type[3] = inst_lh | inst_sh;
assign memop_type[4] = inst_lhu;
assign memop_type[5] = inst_swl | inst_lwl;
assign memop_type[6] = inst_swr | inst_lwr;

wire branch_not_al;
assign branch_not_al = inst_beq | inst_bne | inst_bgez | inst_bgtz | inst_bltz | inst_blez;
wire branch_op;
assign branch_op = branch_not_al | inst_bgezal | inst_bltzal;
wire is_linkr;
assign is_linkr =  inst_jal | inst_jalr | inst_bltzal | inst_bgezal;
wire jump_op;
assign jump_op = inst_j | inst_jr | inst_jal | inst_jalr;

// alu op
assign alu_op[ 0] = inst_addu | inst_addiu | load_op | store_op | is_linkr | inst_add | inst_addi;
assign alu_op[ 1] = inst_subu | inst_sub ;
assign alu_op[ 2] = inst_slt  | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltiu;
assign alu_op[ 4] = inst_and  | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or   | inst_ori;
assign alu_op[ 7] = inst_xor  | inst_xori;
assign alu_op[ 8] = inst_sll  | inst_sllv;
assign alu_op[ 9] = inst_srl  | inst_srlv;
assign alu_op[10] = inst_sra  | inst_srav;
assign alu_op[11] = inst_lui;
assign alu_op[12] = inst_mult;
assign alu_op[13] = inst_multu;
assign alu_op[14] = inst_div;
assign alu_op[15] = inst_divu;
wire mul_div;
assign mul_div = inst_multu | inst_mult | inst_divu | inst_div | inst_mflo | inst_mfhi | inst_mtlo | inst_mthi;

assign src1_is_sa   = inst_sll   | inst_srl | inst_sra;
assign src1_is_pc   = is_linkr;
assign src2_is_imm  = inst_addiu | inst_lui | load_op | store_op | inst_addi | inst_slti | inst_sltiu | 
                      inst_andi | inst_ori | inst_xori;
assign src2_is_8    = is_linkr;
assign res_from_mem = load_op;  
assign dst_is_r31   = is_linkr;
assign dst_is_rt    = inst_addiu | inst_lui | load_op | inst_addi | inst_slti | inst_sltiu | inst_andi | inst_ori | inst_xori;
assign gr_we        = (~store_op & ~branch_not_al & ~inst_jr & ~inst_j & 
                      ~inst_mult & ~inst_multu & ~inst_div & ~inst_divu & ~inst_mthi & ~inst_mtlo)? 4'hf : 4'h0;
assign mem_we       = store_op;
assign dest         = dst_is_r31 ? 5'd31 :
                      dst_is_rt  ? rt    : 
                                   rd;

// exclude all inst                                  
assign reserved_instruction = ~(alu_op || (branch_op | jump_op | mul_div |
                               inst_eret | inst_mfc0 | inst_mtc0 | inst_syscall | inst_break) );

assign rf_raddr1 = rs;
assign rf_raddr2 = rt;
regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

//****** solve hazards by forwarding ******
wire        es_res_from_cp0;
wire        es_load_op;
wire [ 3:0] es_rf_we;
wire [ 4:0] es_waddr;
wire [31:0] es_wdata;
assign { es_res_from_cp0,//42:42
         es_load_op,     //41:41
         es_rf_we,       //40:37
         es_waddr,       //36:32
         es_wdata        //31:0
        } = es_res;

wire        ms_res_from_cp0;
wire [ 3:0] ms_rf_we;
wire [ 4:0] ms_waddr;
wire [31:0] ms_wdata;
assign { ms_res_from_cp0,//41:41
         ms_rf_we,       //40:37
         ms_waddr,       //36:32
         ms_wdata        //31:0
        } = ms_res;

wire [ 3:0] ws_rf_we;
wire [ 4:0] ws_waddr;
wire [31:0] ws_wdata;
assign { interrupt,     //41:41
         ws_rf_we,      //40:37
         ws_waddr,      //36:32
         ws_wdata       //31:0
        } = ws_res;

wire not_forward;
assign not_forward = ((inst_addiu||load_op||store_op||inst_jr||inst_sltu)&& rf_raddr1 ==5'b00000) ||
                     (inst_jal) ||
                     (rf_raddr1 == 5'b0 && rf_raddr2 == 5'b0)? 1'b1 : 1'b0;

assign rs_value[ 7: 0] = (not_forward)?                          rf_rdata1[ 7: 0]:
                         (es_rf_we[0] && es_waddr == rf_raddr1 )? es_wdata[ 7: 0]:
                         (ms_rf_we[0] && ms_waddr == rf_raddr1 )? ms_wdata[ 7: 0]:
                         (ws_rf_we[0] && ws_waddr == rf_raddr1 )? ws_wdata[ 7: 0]: rf_rdata1[ 7: 0];
assign rs_value[15: 8] = (not_forward)?                          rf_rdata1[15: 8]:
                         (es_rf_we[1] && es_waddr == rf_raddr1 )? es_wdata[15: 8]:
                         (ms_rf_we[1] && ms_waddr == rf_raddr1 )? ms_wdata[15: 8]:
                         (ws_rf_we[1] && ws_waddr == rf_raddr1 )? ws_wdata[15: 8]: rf_rdata1[15: 8]; 
assign rs_value[23:16] = (not_forward)?                          rf_rdata1[23:16]:
                         (es_rf_we[2] && es_waddr == rf_raddr1 )? es_wdata[23:16]:
                         (ms_rf_we[2] && ms_waddr == rf_raddr1 )? ms_wdata[23:16]:
                         (ws_rf_we[2] && ws_waddr == rf_raddr1 )? ws_wdata[23:16]: rf_rdata1[23:16];
assign rs_value[31:24] = (not_forward)?                          rf_rdata1[31:24]:
                         (es_rf_we[3] && es_waddr == rf_raddr1 )? es_wdata[31:24]:
                         (ms_rf_we[3] && ms_waddr == rf_raddr1 )? ms_wdata[31:24]:
                         (ws_rf_we[3] && ws_waddr == rf_raddr1 )? ws_wdata[31:24]: rf_rdata1[31:24]; 
                                      
assign rt_value[ 7: 0] = (not_forward)?                          rf_rdata2[ 7: 0]:
                         (es_rf_we[0] && es_waddr == rf_raddr2 )? es_wdata[ 7: 0]:
                         (ms_rf_we[0] && ms_waddr == rf_raddr2 )? ms_wdata[ 7: 0]:
                         (ws_rf_we[0] && ws_waddr == rf_raddr2 )? ws_wdata[ 7: 0]: rf_rdata2[ 7: 0];
assign rt_value[15: 8] = (not_forward)?                          rf_rdata1[15: 8]:
                         (es_rf_we[1] && es_waddr == rf_raddr2 )? es_wdata[15: 8]:
                         (ms_rf_we[1] && ms_waddr == rf_raddr2 )? ms_wdata[15: 8]:
                         (ws_rf_we[1] && ws_waddr == rf_raddr2 )? ws_wdata[15: 8]: rf_rdata2[15: 8]; 
assign rt_value[23:16] = (not_forward)?                          rf_rdata1[23:16]:
                         (es_rf_we[2] && es_waddr == rf_raddr2 )? es_wdata[23:16]:
                         (ms_rf_we[2] && ms_waddr == rf_raddr2 )? ms_wdata[23:16]:
                         (ws_rf_we[2] && ws_waddr == rf_raddr2 )? ws_wdata[23:16]: rf_rdata2[23:16];
assign rt_value[31:24] = (not_forward)?                          rf_rdata1[31:24]:
                         (es_rf_we[3] && es_waddr == rf_raddr2 )? es_wdata[31:24]:
                         (ms_rf_we[3] && ms_waddr == rf_raddr2 )? ms_wdata[31:24]:
                         (ws_rf_we[3] && ws_waddr == rf_raddr2 )? ws_wdata[31:24]: rf_rdata2[31:24];

assign ds_ready_go    = (wr_re == 1'b1)? 1'b0 : 1'b1;
// wr_re == 1 means needs to block  
assign wr_re=(not_forward)? 1'b0:
             (es_load_op && es_waddr == rf_raddr1 && (inst_addiu|| load_op || store_op || inst_jr || inst_sltu))?1'b1:
             (es_load_op && ~inst_jal && (es_waddr == rf_raddr1 || es_waddr == rf_raddr2))?1'b1:
             (es_res_from_cp0 &&(es_waddr==rf_raddr1||es_waddr==rf_raddr2)||ms_res_from_cp0 &&(ms_waddr==rf_raddr1||ms_waddr==rf_raddr2))?1'b1:
              1'b0;

// ====== forwarding ======        
assign rs_eq_rt = (rs_value == rt_value);
assign br_taken = (   inst_beq  &&  rs_eq_rt
                   || inst_bne  && !rs_eq_rt
                   || inst_jal
                   || inst_jr
                   || inst_j
                   || inst_jalr
                   || (inst_bgez || inst_bgezal) && rs_value[31] == 0
                   || inst_bgtz && rs_value[31] == 0 && iszero==0
                   || inst_blez && (rs_value[31] == 1|| iszero==1)
                   || (inst_bltz || inst_bltzal) && rs_value[31] == 1
                   || eret
                  ) && ds_valid;
assign iszero = rs_value == 0;
assign br_target = (branch_op)?             (fs_pc + {{14{imm[15]}}, imm[15:0], 2'b0}) :
                   (inst_jr | inst_jalr)?    rs_value :
                   (eret)               ?    EPC:
                  /*inst_jal || inst_j*/    {fs_pc[31:28], jidx[25:0], 2'b0};

endmodule
