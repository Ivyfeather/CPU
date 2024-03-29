`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    output [`MS_RES          -1:0] ms_res        ,
    output [11:0]                   memexc        ,
    //from data-sram
    input  [31                 :0] data_sram_rdata ,
    input                          data_sram_dataok,
    input  [11:0]                   wbexc,
    output                         tlbwi
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire        ms_res_from_mem;
wire [ 3:0] ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
wire [31:0] from_badvaddr;
wire [31:0] to_badvaddr;
// lab 7
wire [ 6:0] ms_memop_type;  
wire [ 4:0] addr_low2b;
wire [ 11:0] fromexception;
wire [ 11:0] toexception;
wire [41:0] cp0_msg;
wire        at_delay_slot;
wire        es_store;
wire [ 2:0] tlb_type;

assign {tlb_type       ,  //168:166
        es_store       ,  //165:165
        at_delay_slot  ,  //164:164
        cp0_msg        ,  //163:122
        fromexception  ,  //121:115
        addr_low2b[1:0],  //114:113
        ms_memop_type  ,  //112:106
        from_badvaddr  ,  //105:74
        ms_res_from_mem,  //73:73
        ms_gr_we       ,  //72:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;
assign addr_low2b[4:2] = 3'b0; 
assign tlbwi=(tlb_type==3'b010);
wire [31:0] mem_result;
wire [31:0] ms_final_result;
wire word;
wire byte;
wire ubyte;
wire halfword;
wire uhalfword;
wire left;
wire right;
//******* handling exception *******
wire syscall;
wire address_error_read;
wire address_error_write;
wire integer_overflow;
wire breakpoint;
wire reserved_instruction;
wire interrupt;
wire [ 11:0] exception;
wire tlb_modified;
wire [1:0]tlb_refill,tlb_invalid;
assign tlb_modified=0;
assign tlb_refill=2'b0;
assign tlb_invalid=2'b0;
assign exception = {  tlb_modified,
                      tlb_invalid,
                      tlb_refill,
                      interrupt,            //6:6
                      reserved_instruction, //5:5
                      breakpoint,           //4:4
                      integer_overflow,     //3:3
                      address_error_write,  //2:2
                      address_error_read,   //1:1
                      syscall               //0:0
                    };

assign syscall             = 0;
assign address_error_read  = (ms_gr_we[0] &&  word                   && (addr_low2b[1:0]!=2'b00) ) ||
                             (ms_gr_we[0] && (halfword || uhalfword) && (addr_low2b[0]  !=1'b0 ) );
assign address_error_write = 0;
assign integer_overflow    = 0;
assign breakpoint          = 0;
assign reserved_instruction= 0;
assign interrupt           = 0;
// if address_error, then pass addr to ws; otherwise clear it
assign to_badvaddr = (toexception[1] || toexception[2]||toexception[7]||toexception[8]||toexception[9]||toexception[10]||toexception[11])? from_badvaddr : 32'b0;
assign toexception = exception | fromexception; 

assign memexc = toexception;
//======= handling exception =======
assign word = ms_memop_type[0];
assign byte = ms_memop_type[1];
assign ubyte = ms_memop_type[2];
assign halfword = ms_memop_type[3];
assign uhalfword = ms_memop_type[4];
assign left = ms_memop_type[5];
assign right = ms_memop_type[6];

wire [ 3:0] final_gr_we;
wire [ 3:0] lwl_strb;
wire [ 3:0] lwr_strb;
assign lwl_strb = (addr_low2b == 2'b0)?  4'b1000:
                  (addr_low2b == 2'b01)? 4'b1100:
                  (addr_low2b == 2'b10)? 4'b1110:
                  (addr_low2b == 2'b11)? 4'b1111 : 4'b0000;
                  
assign lwr_strb = (addr_low2b == 2'b0)?  4'b1111:
                  (addr_low2b == 2'b01)? 4'b0111:
                  (addr_low2b == 2'b10)? 4'b0011:
                  (addr_low2b == 2'b11)? 4'b0001 : 4'b0000;                    

assign final_gr_we = (ms_gr_we[0] == 0)? 4'h0:  //no need to write RF
                     (left)?             lwl_strb:
                     (right)?            lwr_strb:
                                         4'hf;

assign ms_to_ws_bus = {tlb_type       ,  //157:155
                       at_delay_slot  ,  //154:154
                       cp0_msg        ,  //153:112
                       toexception    ,  //111:105
                       to_badvaddr    ,  //104:73
                       final_gr_we    ,  //72:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc             //31:0
                      };

reg [ 3:0] num_of_unfinished_store;
always @(posedge clk) begin
  if (reset) begin
    num_of_unfinished_store <= 0;
  end
  else if (es_store && ms_valid) begin
    num_of_unfinished_store <= num_of_unfinished_store + 1;
  end
  else if(data_sram_dataok && num_of_unfinished_store>0) begin
    num_of_unfinished_store <= num_of_unfinished_store - 1;
  end
end

assign ms_ready_go    = //not returned store
                        (num_of_unfinished_store != 0)? 1'b0:
                        //not returned load
                        (ms_res_from_mem && num_of_unfinished_store == 0 && ~data_sram_dataok)? 1'b0 :
                        1'b1;

assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if(reset)
        es_to_ms_bus_r<=0;
    else if(wbexc)
        es_to_ms_bus_r  <= 0;
    else if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  <= es_to_ms_bus;
    end
    else if(es_to_ms_valid==0&&ms_to_ws_valid&&ws_allowin)begin
        es_to_ms_bus_r<=0;
    end
end

// modify here for lb /lh 
wire [31:0] lb_rdata;
wire [31:0] lbu_rdata;
wire [31:0] lh_rdata;
wire [31:0] lhu_rdata;
//wire [31:0] lwl_rdata; // just mem_rdata_displaced, use final_gr_we 
//wire [31:0] lwr_rdata;

wire [31:0] mem_rdata_displaced;
assign mem_rdata_displaced = (byte || ubyte || halfword || uhalfword)? data_sram_rdata >> (addr_low2b<<3) :
                             (left)?    data_sram_rdata << ((~addr_low2b)<<3):
                             (right)?   data_sram_rdata >> (addr_low2b<<3):
                             /*word*/   data_sram_rdata;

assign lb_rdata  = { {24{mem_rdata_displaced[7]}}, mem_rdata_displaced[7:0]};
assign lbu_rdata = { 24'h0, mem_rdata_displaced[7:0]};
assign lh_rdata  = { {16{mem_rdata_displaced[15]}}, mem_rdata_displaced[15:0]};
assign lhu_rdata = { 16'h0, mem_rdata_displaced[15:0]};

// add here
assign mem_result = (byte)?      lb_rdata:
                    (ubyte)?     lbu_rdata:
                    (halfword)?  lh_rdata:
                    (uhalfword)? lhu_rdata:
                    /*word, lwl, lwr*/ mem_rdata_displaced;

assign ms_final_result = ms_res_from_mem ? mem_result
                                         : ms_alu_result;                                         
wire res_from_cp0;
wire ms_forward_valid;
assign ms_forward_valid = ms_to_ws_valid&&ms_res_from_mem;
assign res_from_cp0 = (cp0_msg[41:40]==2'b10 || cp0_msg[41:40]==2'b01);                      
assign ms_res={ms_forward_valid, res_from_cp0, final_gr_we, ms_dest, ms_final_result};

endmodule
