`timescale 1ns/1ps

`define REG_MSB             31
`define SYS_BITS            32
`define SYS_BITS_SUB6       26
`define SYS_BITS_SUB10      22
`define CAN_WRITE_DS        (reg_ds != 0)
`define CAN_WRITE_ES        (reg_es != 0)
`define NOT_WRITE_DS        5'b0
`define NOT_WRITE_ES        5'b0

`define ALL_ONE             32'hffff_ffff
`define ALL_ZERO            32'h0000_0000

`define R0                  5'd0
`define SP                  5'd2


module vcpu(
    input           rst,
    input           sck,
    input  [15:0]   cmd,
    output [31:0]   opt,
    output [31:0]   sta
);

reg [31:0]  r[0:31];
reg         cf;
reg         zf;
reg         nf;
reg         vf;
reg [31:0]  n;
reg [31:0]  m;

reg [ 4:0]  reg_ds;
reg [ 4:0]  reg_es;



// add 参数
reg         add_neg_m;
reg         add_with_cf = 0;
reg         add_req = 0;

// add 输出
reg [31:0]  tmp_ds_add;
reg         add_ack = 0;

always @(posedge (add_req != add_ack)) begin
    { tmp_ds_add } = n + (m ^ { `SYS_BITS{ add_neg_m } }) + add_with_cf;
    { add_ack } = add_req;
end

// 按位操作 ========================================
// BITWISE MUX
//
// C0 = B1 ? ~A : A
// C1 = B0 ? 32{1} : B
// C2 = B0 ? 32{1} : A
// C3 = B1 ? ~B : B
// C4 = C0 & C1 | C2 & C3
// 
// FUNC    EXPR                 m1  m0
// and     A & B                0   0
// or      A | B                0   1
// xor     A ^ B                1   0
// nand  ~(A & B) -> ~A | ~B    1   1
reg         bitwise_m0 = 0;
reg         bitwise_m1 = 0;
reg         bitwise_req = 0;
reg         bitwise_ack = 0;
reg [31:0]  tmp_ds_bitwise;

always @(posedge (bitwise_req != bitwise_ack)) begin
    { tmp_ds_bitwise } =
        ((bitwise_m1 ? ~n       : n) & (bitwise_m0 ? `ALL_ONE : m)) | 
        ((bitwise_m0 ? `ALL_ONE : n) & (bitwise_m1 ? ~m       : m));
    { bitwise_ack } = bitwise_req;
end

reg [31:0]  tmp_ds_shift  ;
reg [31:0]  tmp_ds_mul    ;
reg [31:0]  tmp_ds_mem    ;
reg [31:0]  tmp_ds_bl     ;

`define I_ADD               0
`define I_SHIFT             1
`define I_MUL               2
`define I_BITWISE           3
`define I_MEM               4

`define I_MAX               15 /*当 I_MAX 需要变大时需要修改下方 d 的元素个数*/

// i_serial 最大值不能超过 d 数组的索引
reg [ 3:0]  i_serial = 0;

wire[31:0]  d[0:`I_MAX];    // 目的寄存器

assign d     [`I_ADD    ] = tmp_ds_add    ;
assign d     [`I_SHIFT  ] = tmp_ds_shift  ;
assign d     [`I_MUL    ] = tmp_ds_mul    ;
assign d     [`I_BITWISE] = tmp_ds_bitwise;
assign d     [`I_MEM    ] = tmp_ds_mem    ;

always @(posedge sck) begin
    casez(cmd[1:0])
    2'b00: begin
        casez (cmd[15:13])
        // c.addi4spn
        3'b000: begin
            `define RD          {1'b1, cmd[4:2]}
            `define UMM10       {cmd[10:7], cmd[12:11], cmd[5], cmd[6], 2'b0}

            if (`UMM10 != 0) begin
                { i_serial } = `I_ADD;
                { reg_ds } = `RD;
                { n } = r[`SP];
                { m } = `UMM10;

                { add_neg_m } = 0;
                { add_with_cf } = 0;
                { add_req } = !add_ack;
            end else begin
                
            end
        end

        default: begin
            
        end
        endcase
    end
    
    2'b01: begin
        casez (cmd[15:13])
        // addi
        // addiw
        3'b000, 3'b001: begin
            `define RD          (cmd[11:7])
            `define IMM6        {cmd[12], cmd[6:2]}

            { i_serial } = `I_ADD;
            { reg_ds } = `RD;
            { n } = r[`RD];
            { m } = { {`SYS_BITS_SUB6{ cmd[12] }}, `IMM6 };

            { add_neg_m } = 0;
            { add_with_cf } = 0;
            { add_req } = !add_ack;
        end

        // addi16sp
        3'b011: begin
            `define RD          (cmd[11:7])
            `define IMM10       {cmd[12], cmd[4], cmd[3], cmd[2], cmd[5], cmd[6], 4'b0 }

            if (`RD == `SP && `IMM10 != 0) begin
                { i_serial } = `I_ADD;
                { reg_ds } = `SP;
                { n } = r[`RD];
                { m } = { {`SYS_BITS_SUB10{ cmd[12] }}, `IMM10 } ;

                { add_neg_m } = 0;
                { add_with_cf } = 0;
                { add_req } = !add_ack;
            end else begin
                
            end
        end

        default: begin
            
        end
        endcase
    end
    
    2'b10: begin
        casez (cmd[15:12])
        4'b1001: begin
            `define RD          (cmd[11:7])
            `define RS2         (cmd[6:2])

            if (`RD != 0 && `RS2 != `R0) begin
                { i_serial } = `I_ADD;
                { reg_ds } = `RD;
                { n } = r[`RD];
                { m } = r[`RS2];

                { add_neg_m } = 0;
                { add_with_cf } = 0;
                { add_req } = !add_ack;
            end else begin
                
            end
        end

        default: begin
            
        end
        endcase
    end
    
    // 2'b11
    default: begin
        
    end 
    endcase
end endmodule
