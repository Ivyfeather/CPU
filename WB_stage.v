`include "mycpu.h"

module wb_stage(
    input  [ 5:0]                   int           ,
    input                           clk           ,
    input                           reset         ,
    //allowin
    output                          ws_allowin    ,
    //from ms
    input                           ms_to_ws_valid,
    input  [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus  ,
    //to rf: for write back
    output [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus  ,
    output [`WS_RES          -1:0]  ws_res,
    output [ 6:0]                   exception     ,
    //trace debug interface
    output [31:0] debug_wb_pc     ,
    output [ 3:0] debug_wb_rf_wen ,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    output [31:0] EPC
);

reg         ws_valid;
wire        ws_ready_go;

reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
wire [ 3:0] ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
wire [31:0] wb_badvaddr;
wire [41:0] cp0_msg;
wire at_delay_slot;
assign {at_delay_slot  ,  //154:154
        cp0_msg        ,  //153:112
        exception      ,  //111:105
        wb_badvaddr    ,  //104:73
        ws_gr_we       ,  //72:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_pc             //31:0
       } = ms_to_ws_bus_r;

wire syscall;
wire address_error_read;
wire address_error_write;
wire integer_overflow;
wire breakpoint;
wire reserved_instruction;
wire interrupt;
assign {  interrupt,            //6:6
          reserved_instruction, //5:5
          breakpoint,           //4:4
          integer_overflow,     //3:3
          address_error_write,  //2:2
          address_error_read,   //1:1
          syscall               //0:0
        } = exception;


wire mtc0;
wire mfc0;
wire eret;
assign mtc0 = (cp0_msg[41:40] == 2'b01)? 1 : 0;
assign mfc0 = (cp0_msg[41:40] == 2'b10)? 1 : 0;
assign eret = (cp0_msg[41:40] == 2'b11)? 1 : 0;

wire addr_cp0_status;
wire addr_cp0_cause;
wire addr_cp0_EPC;
wire addr_cp0_COUNT;
wire addr_cp0_COMPARE;
wire addr_cp0_BADVADDR;
assign addr_cp0_BADVADDR= (cp0_msg[36:32] == 5'h08)? 1 : 0;
assign addr_cp0_COUNT   = (cp0_msg[36:32] == 5'h09)? 1 : 0;
assign addr_cp0_COMPARE = (cp0_msg[36:32] == 5'h0b)? 1 : 0;
assign addr_cp0_status  = (cp0_msg[36:32] == 5'h0c)? 1 : 0;
assign addr_cp0_cause   = (cp0_msg[36:32] == 5'h0d)? 1 : 0;
assign addr_cp0_EPC     = (cp0_msg[36:32] == 5'h0e)? 1 : 0;



//========= CP0_STATUS =========
wire mtc0_we;
assign mtc0_we = ws_valid && mtc0 && !exception;

reg         cp0_status_bev;
always @(posedge clk) begin
  if (reset)
    cp0_status_bev <= 1'b1; 
end

reg  [ 7:0] cp0_status_IM;
always @(posedge clk) begin
  if (mtc0_we && addr_cp0_status) 
    cp0_status_IM <= cp0_msg[15:8];
end

reg         cp0_status_EXL;
always @(posedge clk) begin
  if (reset) 
    cp0_status_EXL <= 1'b0;
  else if (exception)
    cp0_status_EXL <= 1'b1;
  else if (eret)
    cp0_status_EXL <= 1'b0;
  else if (mtc0_we && addr_cp0_status)
    cp0_status_EXL <= cp0_msg[1]; 
end

reg         cp0_status_IE;
always @(posedge clk) begin
  if (reset)
    cp0_status_IE <= 1'b0;
  else if (mtc0_we && addr_cp0_status)
    cp0_status_IE <= cp0_msg[0];
end

wire [31:0] cp0_status;
assign       cp0_status={9'b0,            //31:23
                         cp0_status_bev,  //22:22
                         6'b0,            //21:16
                         cp0_status_IM,   //15:8
                         6'b0,            //7:2
                         cp0_status_EXL,  //1:1
                         cp0_status_IE    //0:0
                         };

//========= CP0_CAUSE =========
wire count_eq_compare;
wire [5:0] ext_int_in;
assign ext_int_in = int;
assign count_eq_compare = (CP0_COUNT == CP0_COMPARE);

reg          cp0_cause_BD;
always @(posedge clk) begin
  if (reset) 
    cp0_cause_BD <= 1'b0;
  else if (exception && !cp0_status_EXL) 
    cp0_cause_BD <= at_delay_slot;
end

reg          cp0_cause_TI;
always @(posedge clk) begin
  if (reset) 
    cp0_cause_TI <= 1'b0;
  else if (mtc0_we && addr_cp0_COMPARE)
    cp0_cause_TI <= 1'b0;
  else if (count_eq_compare)
    cp0_cause_TI <= 1'b1;
end

reg  [ 7:0]  cp0_cause_IP;
always @(posedge clk) begin
  if (reset) 
    cp0_cause_IP[7:2] <= 6'b0;
  else  begin
    cp0_cause_IP[7]   <= ext_int_in[5] | cp0_cause_TI;
    cp0_cause_IP[6:2] <= ext_int_in[4:0];
  end
end
always @(posedge clk) begin
  if (reset) 
    cp0_cause_IP[1:0] <= 2'b0;
  else if (mtc0_we && addr_cp0_cause) 
    cp0_cause_IP[1:0] <= cp0_msg[9:8];
end

reg  [ 4:0]  cp0_cause_ExcCode;
wire [ 4:0]  wb_excode;
// interrupt has the highest priority
assign wb_excode = (interrupt)?           6'h00 :
                   (address_error_read)?  6'h04 :
                   (reserved_instruction)?6'h0a:
                   (syscall)?             6'h08 :
                   (integer_overflow)?    6'h0c :
                   (breakpoint)?          6'h09 :
                   (address_error_write)? 6'h05 :6'h00;
always @(posedge clk) begin
  if (reset) 
    cp0_cause_ExcCode <= 5'b0;
  else if (exception) 
    cp0_cause_ExcCode <= wb_excode;
end

wire [31:0]  cp0_cause;
assign       cp0_cause={
                         cp0_cause_BD,      //31:31
                         cp0_cause_TI,      //30:30
                         14'b0       ,      //29:16
                         cp0_cause_IP,      //15:8
                         1'b0        ,      //7:7
                         cp0_cause_ExcCode, //6:2
                         2'b00              //1:0
                         };  
              
//========= CP0_EPC =========
reg [31:0] cp0_EPC;
always @(posedge clk)
begin
    if(exception && !cp0_status_EXL)
      cp0_EPC <= at_delay_slot? ws_pc - 3'h4 : ws_pc ;
    else if(mtc0_we && addr_cp0_EPC)
      cp0_EPC <= cp0_msg[31:0];
end 
//========= CP0_COUNT =========
reg [31:0] CP0_COUNT;
reg        tick;
always @(posedge clk) begin
  if (reset) tick <= 1'b0;
  else       tick <= ~tick;
  if (mtc0_we && addr_cp0_COUNT)
    CP0_COUNT <= cp0_msg[31:0];
  else if (tick)
    CP0_COUNT <= CP0_COUNT + 1'b1;
end
//========= CP0_COMPARE =========
reg [31:0] CP0_COMPARE;
always @(posedge clk) begin
  if (reset) 
    CP0_COMPARE <= 32'b0;
  else if (mtc0_we && addr_cp0_COMPARE) 
    CP0_COMPARE <= cp0_msg[31:0];
end
//========= CP0_BADVADDR =========
reg  [31:0] CP0_BADVADDR;
  // pc addr_error comes first
always @(posedge clk) begin
  if (exception && (address_error_read || address_error_write) ) 
    CP0_BADVADDR <= wb_badvaddr;
end


wire [3 :0] rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //40:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if(reset)
        ms_to_ws_bus_r <= 0;
    else if(exception)
        ms_to_ws_bus_r <= 0;
    else if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end


assign rf_we    = (~ws_valid || exception)? 4'h0:
                                 ws_gr_we;

assign rf_waddr = ws_dest;
assign rf_wdata =(mfc0 && addr_cp0_status)?  cp0_status:
                 (mfc0 && addr_cp0_cause)?   cp0_cause:
                 (mfc0 && addr_cp0_EPC)?     cp0_EPC: 
                 (mfc0 && addr_cp0_COMPARE)? CP0_COMPARE:
                 (mfc0 && addr_cp0_COUNT)?   CP0_COUNT:
                 (mfc0 && addr_cp0_BADVADDR)?CP0_BADVADDR:
                 ws_final_result;

wire mark_interrupt;
assign mark_interrupt = (~cp0_status_IE | cp0_status_EXL)? 1'b0 : 
                        ((cp0_cause_IP & cp0_status_IM) == 8'b0)? 1'b0 : 1'b1;


assign ws_res={mark_interrupt,rf_we,ws_dest,rf_wdata};

// debug info generate
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_wen   = (mfc0)? 4'b1111:
                           (exception || mtc0)?4'b0:
                           {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = rf_wdata;
assign EPC =cp0_EPC;
endmodule
