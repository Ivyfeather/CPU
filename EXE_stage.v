`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    input  [6:0]                   wbexc         ,
    input  [6:0]                   memexc        ,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    output [`ES_RES          -1:0] es_res,
    // data sram interface
    output           data_sram_req   ,
    output           data_sram_wr    ,
    output [ 1:0]    data_sram_size  ,
    output [31:0]    data_sram_addr  ,
    output [31:0]    data_sram_wdata ,
    input            data_sram_addrok

//old
    // output        data_sram_en   ,
    // output [ 3:0] data_sram_wen  ,
    // output [31:0] data_sram_addr ,
    // output [31:0] data_sram_wdata
);

reg         es_valid      ;
reg[31:0]   hi;
reg[31:0]   lo;
wire        es_ready_go   ;
reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
wire [15:0] es_alu_op     ;
wire        es_load_op    ;
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
wire        es_src2_is_imm; 
wire        es_src2_is_8  ;
wire [ 3:0] es_gr_we      ;
wire        es_mem_we     ;
wire [ 4:0] es_dest       ;
wire [31:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;
wire [31:0] es_inst;
wire [31:0] hi1;
wire [31:0] lo1;
// lab 7
wire [ 6:0] es_memop_type;
wire [ 4:0] addr_low2b;
wire word;
wire byte;
wire halfword;
wire left;
wire right;
wire [31:0] es_badvaddr;

//******* handling exception *******
wire [6:0]  fromexception;
wire [6:0]  toexception;
wire [41:0] cp0_msg;

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
assign syscall          = 0;
assign address_error_read  = 0;
assign address_error_write = (es_mem_we && word     && addr_low2b[1:0]!=2'b00 ) ||
                             (es_mem_we && halfword && addr_low2b[0]  !=1'b0  );

wire [31:0] bad_pc;
// has addr_error_read in IF
assign es_badvaddr = fromexception[1]? bad_pc : es_alu_result;

wire add_overflow;
wire sub_overflow;
assign add_overflow = ((es_alu_src1[31] == 0) && (es_alu_src2[31] == 0) && (alu_result[31] == 1)) | 
                      ((es_alu_src1[31] == 1) && (es_alu_src2[31] == 1) && (alu_result[31] == 0));
assign sub_overflow = ((es_alu_src1[31] == 0) && (es_alu_src2[31] == 1) && (alu_result[31] == 1)) | 
                      ((es_alu_src1[31] == 1) && (es_alu_src2[31] == 0) && (alu_result[31] == 0));
assign integer_overflow =   (es_alu_op[0] & add_overflow) | 
                            (es_alu_op[1] & sub_overflow);

assign breakpoint       = 0;
assign reserved_instruction = 0;
assign interrupt        = 0;

// integer overflow when add/addi/subu (fromexception[3] == 1)
assign toexception[6:4]  = exception[6:4] | fromexception[6:4]; 
assign toexception[3]    = integer_overflow & fromexception[3];
assign toexception[2:0]  = exception[2:0] | fromexception[2:0]; 
//======= handling exception =======
wire        at_delay_slot;

assign {bad_pc         ,  //279:248
        at_delay_slot  ,  //247:247
        cp0_msg        ,  //246:205
        fromexception  ,  //204:198
        es_memop_type  ,  //197:191
        es_inst        ,  //190:159
        es_alu_op      ,  //158:143
        es_load_op     ,  //142:142
        es_src1_is_sa  ,  //141:141
        es_src1_is_pc  ,  //140:140
        es_src2_is_imm ,  //139:139
        es_src2_is_8   ,  //138:138
        es_gr_we       ,  //137:134
        es_mem_we      ,  //133:133
        es_dest        ,  //132:128
        es_imm         ,  //127:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;
wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;
wire [31:0] alu_result;

// ****** mul & div operations ******
wire tvalid3;
wire tready1;
wire tready2;
reg tvalid1;
reg tvalid2;
reg count;
wire[63:0] div_result;
wire[63:0] divu_result;
wire[63:0] mult_result;
wire[63:0] multu_result;
wire div_ready_go;
wire[31:0] div_src1;
wire[31:0] div_src2;
assign div_src1=(es_alu_op[14] && es_alu_src1[31]==1)? ~es_alu_src1 + 1:
                                                        es_alu_src1;
assign div_src2=(es_alu_op[14] && es_alu_src2[31]==1)? ~es_alu_src2 + 1:
                                                        es_alu_src2;
assign div_ready_go=(tvalid3==0 && (es_alu_op[14] | es_alu_op[15]))? 1'b0:
                                                                     1'b1;
mydiv mydiv(
      .aclk(clk),
      .s_axis_divisor_tvalid(tvalid1),
      .s_axis_divisor_tready(tready1),
      .s_axis_divisor_tdata(div_src2),
      .s_axis_dividend_tvalid(tvalid2),
      .s_axis_dividend_tready(tready2),
      .s_axis_dividend_tdata(div_src1),
      .m_axis_dout_tvalid(tvalid3),
      .m_axis_dout_tdata(divu_result)
);
assign mult_result = $signed(es_alu_src1) * $signed(es_alu_src2);
assign multu_result= es_alu_src1 * es_alu_src2;     
assign div_result[31:0]=(es_alu_src1[31])? ~divu_result[31:0] + 1:
                                            divu_result[31:0];
assign div_result[63:32]=(es_alu_src1[31] ^ es_alu_src2[31])? ~divu_result[63:32] + 1:
                                                               divu_result[63:32];
always @(posedge clk)
begin
   if(reset)
     begin
      tvalid1<=0;
      tvalid2<=0;
      count<=0;
     end
    else if((es_alu_op[14]|es_alu_op[15])&&(tvalid1==0&&tvalid2==0)&&count==0)
     begin
      tvalid1<=1;
      tvalid2<=1;
     end
    else if((tvalid1==1&&tvalid2==1)&&tready1==1'b1&&tready1==1'b1)
     begin
       tvalid1<=0;
       tvalid2<=0;
       count<=1;
      end
     else if(count==1&&tvalid3==1'b1)
       begin
         count<=0;
       end
 end
// ====== mul & div operations ======

// ****** forwarding ******
wire        es_res_from_mem;
wire        res_from_cp0;
assign      res_from_cp0 = cp0_msg[41:40]==2'b10||cp0_msg[41:40]==2'b01;
assign es_res={ res_from_cp0,//42:42
                es_load_op,  //41:41
                es_gr_we,    //40:37
                es_dest,     //36:32
                es_alu_result//31:0
               };
assign es_res_from_mem = es_load_op;
// ====== forwarding ======

wire Is_store_op;
assign Is_store_op = (data_sram_req && data_sram_wr && data_sram_addrok)? 1'b1:
                      1'b0;

assign es_to_ms_bus = (es_ready_go==1'b0)?0:
                      {Is_store_op    ,  //165:165
                       at_delay_slot  ,  //164:164
                       cp0_msg        ,  //163:122
                       toexception    ,  //121:115
                       addr_low2b[1:0],  //114:113
                       es_memop_type  ,  //112:106
                       es_badvaddr    ,  //105:74
                       es_res_from_mem,  //73:73
                       es_gr_we       ,  //72:69
                       es_dest        ,  //68:64
                       es_alu_result  ,  //63:32
                       es_pc             //31:0
                      };

assign es_ready_go    = (div_ready_go==1'b0)?1'b0:
                        (data_sram_req && ~data_sram_addrok)? 1'b0:     ////// load_op  addr not accepted
                        1'b1;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid = es_valid && es_ready_go;
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end
    if(wbexc)
        ds_to_es_bus_r <=32'h0;
    else if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
    else if(div_ready_go==0 && (es_alu_op[14]||es_alu_op[15]) );
    else if((es_load_op||es_mem_we) && ~data_sram_addrok) ;
    else 
        ds_to_es_bus_r<=0;
end

assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                                      es_rs_value;
assign es_alu_src2 = es_src2_is_imm ? es_imm : 
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (alu_result   )
    );
assign es_alu_result=(es_inst[31:26]==6'b000000 && es_inst[5:0]==6'b010000)?hi:
                     (es_inst[31:26]==6'b000000 && es_inst[5:0]==6'b010010)?lo:
                     alu_result;
assign addr_low2b[1:0] = es_alu_result[1:0];                   
assign addr_low2b[4:2] = 3'b0;

always@(posedge clk)
   begin
      if(wbexc || memexc || exception);
      else if(es_inst[31:26]==6'b000000&&es_inst[5:0]==6'b010001)
           hi<=es_rs_value;
      else
           hi<=hi1;
   end
always@(posedge clk)
    begin
       if(wbexc || memexc || exception);
       else if(es_inst[31:26]==6'b000000&&es_inst[5:0]==6'b010011)
           lo<=es_rs_value;
       else
           lo<=lo1;
    end

//****** assessing memory operations ******
assign word = es_memop_type[0];
assign byte = es_memop_type[1];
assign halfword = es_memop_type[3];
assign left = es_memop_type[5];
assign right = es_memop_type[6];

wire [ 3:0] swl_wen;
wire [ 3:0] swr_wen;
assign swl_wen = (addr_low2b == 2'b0)?  4'b0001:
                 (addr_low2b == 2'b01)? 4'b0011:
                 (addr_low2b == 2'b10)? 4'b0111:
                 (addr_low2b == 2'b11)? 4'b1111:
                                        4'b1111;
                 
assign swr_wen = (addr_low2b == 2'b0)?  4'b1111:
                 (addr_low2b == 2'b01)? 4'b1110:
                 (addr_low2b == 2'b10)? 4'b1100:
                 (addr_low2b == 2'b11)? 4'b1000:
                                        4'b1111;

reg data_sram_req_r;
always @(posedge clk) begin
  if (reset) begin
    data_sram_req_r <= 1'b0;
  end
  //load

  //higher prior
  else if (ds_to_es_valid && es_allowin) begin
    data_sram_req_r <= 1'b1;
  end
  //store
  // else if (ds_to_es_valid && es_allowin) begin
  //   data_sram_req_r <= 1'b1;
  // end
  else if (data_sram_addrok) begin
    data_sram_req_r <= 1'b0;
  end
  else if ((es_load_op||es_mem_we) && data_sram_req_r==1'b1)begin
    
  end
end
//since es_load_op and es_mem_we will appear after edge
// while in sequential logic upahead, ds_to_es_valid and es_allowin is high before edge
assign data_sram_req= (es_load_op || es_mem_we)?  data_sram_req_r: 1'b0;
assign data_sram_wr = es_mem_we;

//assign data_sram_en    = 1'b1;
wire data_sram_wstrb;
assign data_sram_wstrb  = (~es_mem_we || ~es_valid)? 4'h0:   //not store
                         (memexc || wbexc || exception)? 4'h0:
                         (byte)?        (4'b0001) << addr_low2b:
                         (halfword)?    (4'b0011) << addr_low2b:
                         (left)?        swl_wen:
                         (right)?       swr_wen:
                         /*word*/       4'hf;
                  
assign data_sram_size = (halfword)? 2'd1:
                        (byte)?     2'd0:
                        (left && addr_low2b[1:0]==0)? 2'd0: 
                        (left && addr_low2b[1:0]==1)? 2'd1:
                        (left && addr_low2b[1:0]==2)? 2'd2:
                        (left && addr_low2b[1:0]==3)? 2'd2:

                        (right && addr_low2b[1:0]==0)? 2'd2:
                        (right && addr_low2b[1:0]==1)? 2'd2:
                        (right && addr_low2b[1:0]==2)? 2'd1:
                        (right && addr_low2b[1:0]==3)? 2'd0:
                        2'd2;





// effective address
wire [31:0] swl_data;
wire [31:0] swr_data;
assign swl_data = es_rt_value >> ((~addr_low2b)<<3);
assign swr_data = es_rt_value << (addr_low2b<<3);

assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = (byte)?     {4{es_rt_value[ 7:0]}}:
                         (halfword)? {2{es_rt_value[15:0]}}:
                         (left)?     swl_data:
                         (right)?    swr_data:
                                     es_rt_value;


assign hi1=(es_alu_op[12])?mult_result[63:32]:
           (es_alu_op[13])?multu_result[63:32]:
           (es_alu_op[14])?div_result[31:0]:
           (es_alu_op[15])?divu_result[31:0]:
            hi;
assign lo1=(es_alu_op[12])?mult_result[31:0]:
           (es_alu_op[13])?multu_result[31:0]:
           (es_alu_op[14])?div_result[63:32]:
           (es_alu_op[15])?divu_result[63:32]:
           lo;
//====== assessing memory operations ======
endmodule
