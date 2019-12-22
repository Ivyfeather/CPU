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
    output [ 11:0]                   exception     ,

//write port
    output we,
    output [ 3:0]w_index,
    output [18:0]w_vpn2,
    output [ 7:0]w_asid,
    output w_g,

    output [19:0]w_pfn0,
    output [ 2:0]w_c0,
    output w_d0,
    output w_v0,

    output [19:0] w_pfn1,
    output [ 2:0] w_c1,
    output w_d1,
    output w_v1,

 // read port
    output [ 3:0] r_index,
    input  [18:0] r_vpn2,
    input  [ 7:0] r_asid,
    input  r_g,

    input  [19:0] r_pfn0,
    input  [ 2:0] r_c0,
    input  r_d0,
    input  r_v0,

    input  [19:0] r_pfn1,
    input  [ 2:0] r_c1,
    input  r_d1,
    input  r_v1,

    output TLBP,
    output [31:0] EntryHi,
    input  [ 5:0] TLBP_result,
    //trace debug interface
    output  [31:0] debug_wb_pc     ,
    output  [ 3:0] debug_wb_rf_wen ,
    output  [ 4:0] debug_wb_rf_wnum,
    output  [31:0] debug_wb_rf_wdata,
    output  [31:0] EPC
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
wire [ 2:0] tlb_type;
assign {tlb_type       ,  //157:155
        at_delay_slot  ,  //154:154
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
wire tlb_modified;
wire [1:0]tlb_refill,tlb_invalid;
assign {  tlb_modified,
          tlb_invalid,
          tlb_refill,
          interrupt,            //6:6
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

wire tlbp;
wire tlbwi;
wire tlbr;
reg tlbp_r;
assign  { tlbp,      //2:2
          tlbwi,     //1:1
          tlbr       //0:0
         } = tlb_type;

wire addr_cp0_status;
wire addr_cp0_cause;
wire addr_cp0_EPC;
wire addr_cp0_COUNT;
wire addr_cp0_COMPARE;
wire addr_cp0_BADVADDR;
wire addr_cp0_EntryHi;
wire addr_cp0_EntryLo0;
wire addr_cp0_EntryLo1;
wire addr_cp0_Index;

assign addr_cp0_Index   = (cp0_msg[36:32] == 5'h00)? 1 : 0;
assign addr_cp0_EntryLo0= (cp0_msg[36:32] == 5'h02)? 1 : 0;
assign addr_cp0_EntryLo1= (cp0_msg[36:32] == 5'h03)? 1 : 0;
assign addr_cp0_BADVADDR= (cp0_msg[36:32] == 5'h08)? 1 : 0;
assign addr_cp0_COUNT   = (cp0_msg[36:32] == 5'h09)? 1 : 0;
assign addr_cp0_EntryHi = (cp0_msg[36:32] == 5'h0a)? 1 : 0;
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
assign wb_excode = (tlb_refill[0]||tlb_invalid[0])?       6'h02 :
                   (tlb_refill[1]||tlb_invalid[1])?       6'h03 :
                   (tlb_modified)?        6'h01 :
                   (interrupt)?           6'h00 :
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
  if (exception && (address_error_read || address_error_write||tlb_refill||tlb_invalid||tlb_modified) ) 
    CP0_BADVADDR <= wb_badvaddr;
end


//========= CP0_EntryHi =========
reg [18:0] VPN2;
reg [ 7:0] ASID;
always @(posedge clk)
begin
    if(reset) begin
      VPN2 <= 0;
      ASID <= 0;
    end
    if(mtc0_we && addr_cp0_EntryHi) begin
      VPN2 <= cp0_msg[31:13];
      ASID <= cp0_msg[ 7: 0];
    end
    else if (tlb_refill||tlb_invalid||tlb_modified)begin
      VPN2 <= wb_badvaddr[31:13];
      ASID <= cp0_msg[7:0];
    end
    else if (tlbr && ws_valid && !exception) begin
      VPN2 <= r_vpn2;
      ASID <= r_asid;
    end

end 




wire [31:0] CP0_EntryHi;
assign CP0_EntryHi = {
                       VPN2,  //31:13
                       5'b0,  //12:8
                       ASID   //7:0
                      };
//========= CP0_EntryLo =========
//31~26:0,    25~6:PFN,   5~3:C,    2:D,    1:V,    0:G 
reg [19:0] PFN0;
reg [ 2:0] C0;
reg D0;
reg V0;
reg G0;
always @(posedge clk) begin
  if (reset) begin
    PFN0 <= 0;
    C0   <= 0;
    D0   <= 0;
    V0   <= 0;
    G0   <= 0; 

  end
  else if (mtc0_we && addr_cp0_EntryLo0) begin
    PFN0 <= cp0_msg[25:6];
    C0   <= cp0_msg[ 5:3];
    D0   <= cp0_msg[ 2];
    V0   <= cp0_msg[ 1];
    G0   <= cp0_msg[ 0];
  end
  else if (tlbr && ws_valid && !exception) begin
    PFN0 <= r_pfn0;
    C0   <= r_c0;
    D0   <= r_d0;
    V0   <= r_v0;
    G0   <= r_g;    
  end
end

reg [19:0] PFN1;
reg [ 2:0] C1;
reg D1;
reg V1;
reg G1;
always @(posedge clk) begin
  if (reset) begin
    PFN1 <= 0;
    C1   <= 0;
    D1   <= 0;
    V1   <= 0;
    G1   <= 0; 

  end
  else if (mtc0_we && addr_cp0_EntryLo1) begin
    PFN1 <= cp0_msg[25:6];
    C1   <= cp0_msg[ 5:3];
    D1   <= cp0_msg[ 2];
    V1   <= cp0_msg[ 1];
    G1   <= cp0_msg[ 0];
  end
  else if (tlbr && ws_valid && !exception) begin
    PFN1 <= r_pfn1;
    C1   <= r_c1;
    D1   <= r_d1;
    V1   <= r_v1;
    G1   <= r_g;    
  end
end

wire [31:0] CP0_EntryLo0;
wire [31:0] CP0_EntryLo1;
assign CP0_EntryLo0 = {6'b0, PFN0, C0, D0, V0, G0};
assign CP0_EntryLo1 = {6'b0, PFN1, C1, D1, V1, G1};

//========= CP0_Index =========
//Index 3~0 bits
reg   Found;
reg   [3:0] Index;
always @(posedge clk)
begin
    if(reset) begin
      Index <= 4'b0;
      Found <= 1'b0;
    end
    else if(mtc0_we && addr_cp0_Index) begin
      //write to Found not allowed
      Index <= cp0_msg[ 3:0];
    end
    else if (tlbp && TLBP_valid && ws_valid && !exception) begin ////// refer to mtc0_we = ws_valid && mtc0 && !exception; ???
      Found <= TLBP_found;
      Index <= TLBP_index;
    end

end 

wire  [31:0] CP0_Index;
assign CP0_Index = {
                    Found,  //31:31
                    27'b0,  //30:4
                    Index   //3:0
                    };

// TLB
reg sign; 
always @(posedge clk)
begin
    if(reset)
       sign<=0;
    else
       sign<=tlbp;
end
always @(posedge clk)
begin
    if(reset)
       tlbp_r<=0;
    else if(tlbp==1&&sign==0)
       tlbp_r<=1;
    else if(tlbp_r==1)
       tlbp_r<=0;
end
assign TLBP = tlbp_r;
assign EntryHi = CP0_EntryHi;

wire TLBP_valid;
wire TLBP_found;
wire [3:0] TLBP_index;
assign {TLBP_valid,   //5:5
        TLBP_found,   //4:4
        TLBP_index    //3:0
      } = TLBP_result;

//TLBWI
assign we = tlbwi; //////???
assign w_index = Index;
assign w_vpn2 = VPN2;
assign w_asid = ASID;
assign w_g = G0 & G1;

assign w_pfn0 = PFN0;
assign w_c0 = C0;
assign w_d0 = D0;
assign w_v0 = V0;

assign w_pfn1 = PFN1;
assign w_c1 = C1;
assign w_d1 = D1;
assign w_v1 = V1;

assign r_index = Index;


wire [3 :0] rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //40:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

assign ws_ready_go = (tlbp && tlbp_r==0)? 1'b0 : 1'b1;
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

assign rf_waddr = (mfc0)?cp0_msg[4:0]:
                  ws_dest;
assign rf_wdata =(mfc0 && addr_cp0_status)?  cp0_status:
                 (mfc0 && addr_cp0_cause)?   cp0_cause:
                 (mfc0 && addr_cp0_EPC)?     cp0_EPC: 
                 (mfc0 && addr_cp0_COMPARE)? CP0_COMPARE:
                 (mfc0 && addr_cp0_COUNT)?   CP0_COUNT:
                 (mfc0 && addr_cp0_BADVADDR)?CP0_BADVADDR:
                 (mfc0 && addr_cp0_EntryHi)? CP0_EntryHi:
                 (mfc0 && addr_cp0_EntryLo0)?CP0_EntryLo0:
                 (mfc0 && addr_cp0_EntryLo1)?CP0_EntryLo1:
                 (mfc0 && addr_cp0_Index)?   CP0_Index:                 
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
