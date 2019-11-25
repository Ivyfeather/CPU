`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    input  [6:0]                   wbexc          ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_req   ,
    output        inst_sram_wr    ,
    output [ 1:0] inst_sram_size  ,
    output [31:0] inst_sram_addr  ,
    output [31:0] inst_sram_wdata ,
    input  [31:0] inst_sram_rdata ,
    input         inst_sram_addrok,
    input         inst_sram_dataok
// old
    // output        inst_sram_en   ,
    // output [ 3:0] inst_sram_wen  ,
    // output [31:0] inst_sram_addr ,
    // output [31:0] inst_sram_wdata,
    // input  [31:0] inst_sram_rdata    
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire         br_taken;
wire [ 31:0] br_target;
wire         eret;
assign {eret, br_taken, br_target} = br_bus;

wire [31:0] fs_inst;
wire [6:0]  toexception;
reg  [31:0] fs_pc;
wire [31:0] bad_pc;
wire PC_addr_error;

// to store br_target
reg         buf_valid;
reg [31:0]  buf_npc;
// truenpc = buf_valid? buf_pc : nextpc;
// wire has_jump_to_brtarget;
// assign has_jump_to_brtarget = nextpc == br_target;
reg [ 1:0]  branch;
always @(posedge clk) begin
    if (reset) begin
        branch <= 2'b0;
    end

    if (br_taken && inst_sram_addrok) begin //addr in delay slot accepted
        branch <= branch + 2;
    end
    else if (br_taken) begin
        branch <= branch + 1;
    end
    else if (branch && inst_sram_addrok) begin
        branch <= branch + 1;
    end
end


always @(posedge clk) begin
    if (reset) begin
        buf_valid <= 1'b0;
    end
    else if(buf_valid && inst_sram_addrok) begin
        buf_valid <= 1'b0;
        branch <= 1'b0;
    end
    else if (branch == 2 ) begin // has sent pc in delay slot /////
        buf_valid <= 1'b1;
    end

    if(br_taken) begin
        buf_npc <= br_target;
    end

end


assign bad_pc = (PC_addr_error)? fs_pc : 32'b0;
assign fs_to_ds_bus = {bad_pc,       //102:71
                       toexception, //70:64
                       fs_inst ,    //63:32
                       fs_pc        //31:0   
                    };

// pre-IF stage
////// evenif addrok lasts only 1 cycle  ...  is this ok?
assign to_fs_valid  = ~reset && inst_sram_addrok;
assign seq_pc       = fs_pc + 3'h4;
//old
// assign nextpc       = wbexc ? 32'hbfc00380:
//                       br_taken ? br_target : 
//                       seq_pc; 
assign nextpc = wbexc? 32'hbfc00380:
                buf_valid? buf_npc:
                seq_pc;



// PC addr error
assign PC_addr_error = (fs_pc[1:0] != 2'b00)? 1 : 0;
assign toexception = {  5'b0,           //6:2
                        PC_addr_error,  //1:1
                        1'b0            //0:0   
                    };

// IF stage
assign fs_ready_go    = inst_sram_dataok;
assign fs_allowin     = (wbexc)?1'b1:
                         !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid =  fs_valid && fs_ready_go;
always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'hbfbffffc;  //trick: to make nextpc be 0xbfc00000 during reset 
    end
    //else if(wbexc)
    //    fs_pc <= 32'hbfc00380;
    else if(eret || wbexc)
        fs_pc <= nextpc;
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

// old
// assign inst_sram_en    = to_fs_valid && fs_allowin;
// assign inst_sram_wen   = 4'h0;
// assign inst_sram_addr  = nextpc;
// assign inst_sram_wdata = 32'b0;
reg inst_sram_req_r;
always @(posedge clk) begin
    if (reset) begin
        inst_sram_req_r <= 1'b0;
    end
    else if (inst_sram_addrok) begin //addr accepted, do not send req anymore
       inst_sram_req_r <= 1'b0; 
    end
    else if (fs_allowin) begin //can flow to IF, req = 1 ////
        inst_sram_req_r <= 1'b1;
    end

end

assign inst_sram_req = inst_sram_req_r;

assign inst_sram_addr = nextpc;

// IF do not write Inst Sram
assign inst_sram_wr = 1'b0;
assign inst_sram_size = 2'd2;
assign inst_sram_wdata = 32'b0;

// since it is only available when valid/ready_go signals are high
assign fs_inst         = inst_sram_rdata;

endmodule
