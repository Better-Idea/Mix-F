// 目标：低功耗设计
`timescale 1ns/1ps

`define PC              15
`define INT_MSB         31
`define ALL_ONE         32'hffff_ffff
`define ALL_ZERO        32'h0000_0000

module vcpu(
    input           sck,
    input [15:0]    cmd
);
    reg [31:0] r[0:15];
    reg [31:0] a;   // adddition
    reg [31:0] b;   // temp
    reg in_it_block = 0;
    reg cf = 0;
    reg zf = 0;
    reg nf = 0;
    reg vf = 0;
    
    reg tmp_cf = 0;
    reg tmp_zf = 0;
    reg tmp_nf = 0;
    reg tmp_vf = 0;
    reg sub_cf = 0;
    reg need_modify_vf = 0;

    reg m0;
    reg m1;
always @(posedge sck) begin
    casez(cmd[15:8])
        // 移位操作
        8'b000?_????: begin
            `define MODE        cmd[12:11]
            `define WITH_SIGN   cmd[12]
            `define IMM5        cmd[10:6]
            `define RM          cmd[5:3]
            `define RD          cmd[2:0]
            
            if (`MODE == 0) begin
                { tmp_cf, r[`RD] } = { r[`RM] } << `IMM5;
            end else begin
                { r[`RD], tmp_cf } = { 
                    `WITH_SIGN && r[`RM][`INT_MSB] ? `ALL_ONE : `ALL_ZERO, r[`RM], 1'b0
                } >> `IMM5;
            end

            if (`MODE != 0 && !in_it_block) begin
                nf = r[`RD][`INT_MSB];
                zf = r[`RD] == 0;
                cf = tmp_cf;
            end

            // TODO: opcode 2'b11 invalid
            `undef MODE
            `undef WITH_SIGN
            `undef IMM5
            `undef RM
            `undef RD
        end

        // 加减法
        8'b0001_????: begin
            `define IS_IMM_RM   cmd[10]

            // cmd[9]
            // - 0:add
            // - 1:sub
            `define IS_SUB      cmd[9]

            `define RM          cmd[8:6]
            `define RN          cmd[5:3]
            `define RD          cmd[2:0]

            { a } = `IS_IMM_RM ? `RM : r[`RM];
            { b, sub_cf } = `IS_SUB ? { ~a, 1'b1 } : { a, 1'b0 };
            { tmp_vf } = r[`RN][`INT_MSB] == b[`INT_MSB];
            { tmp_cf, r[`RD] } = r[`RN] + b + sub_cf;

            if (`RD != `PC && !in_it_block) begin
                nf = r[`RD][`INT_MSB];
                zf = r[`RD] == 0;
                cf = tmp_cf;

                // 操作前相同符号位，相加后符号位不同了就表示溢出了
                vf = tmp_vf ? tmp_vf != r[`RD][`INT_MSB] : 0;
            end

            `undef IS_IMM_RM
            `undef IS_SUB
            `undef RM
            `undef RN
            `undef RD
        end

        // 与立即数加、减、赋值、比较
        8'b001?_????: begin
            `define MODE        cmd[12:11]
            `define IS_MOV      (`MODE == 0)
            `define IS_NOT_MOV  (`MODE != 0)
            `define IS_NOT_CMP  (`MODE != 1)
            `define IS_SUB      cmd[11]
            `define RD          cmd[10:8]
            `define IMM8        cmd[7:0]

            { b, sub_cf } = `IS_SUB ? { ~`IMM8, 1'b1 }: { `IMM8, 1'b0 };
            { a } = `IS_MOV ? 0 : r[`RD];
            { tmp_vf } = r[`RD][`INT_MSB] == b[`INT_MSB];
            { tmp_cf, b } = a + b + sub_cf;

            // 不限制寄存器
            if (!in_it_block) begin
                nf = r[`RD][`INT_MSB];
                zf = r[`RD] == 0;
                cf = tmp_cf;

                // mov 不修改 vf
                if (`IS_NOT_MOV) begin
                    vf = tmp_vf ? tmp_vf != r[`RD][`INT_MSB] : 0;
                end
            end

            // cmp 不修改目的寄存器
            if (`IS_NOT_CMP) begin
                r[`RD] = b;
            end

            `undef MODE
            `undef IS_MOV
            `undef IS_NOT_MOV
            `undef IS_NOT_CMP
            `undef IS_SUB
            `undef RD
            `undef IMM8
        end

        8'b0100_00??: begin
            `define IS_AND      (cmd[9:6] == 4'b0000)
            `define IS_XOR      (cmd[9:6] == 4'b0001)
            `define IS_LSL      (cmd[9:6] == 4'b0010)
            `define IS_LSR      (cmd[9:6] == 4'b0011)
            `define IS_ASR      (cmd[9:6] == 4'b0100)
            `define IS_ADC      (cmd[9:6] == 4'b0101)
            `define IS_SBC      (cmd[9:6] == 4'b0110)
            `define IS_ROR      (cmd[9:6] == 4'b0111)
            `define IS_TST      (cmd[9:6] == 4'b1000)
            `define IS_RSB      (cmd[9:6] == 4'b1001)
            `define IS_CMP      (cmd[9:6] == 4'b1010)
            `define IS_CMN      (cmd[9:6] == 4'b1011)
            `define IS_ORR      (cmd[9:6] == 4'b1100)
            `define IS_MUL      (cmd[9:6] == 4'b1101)
            `define IS_BIC      (cmd[9:6] == 4'b1110)
            `define IS_MVN      (cmd[9:6] == 4'b1111)
            `define IS_NOT_TST  (!`IS_TST)
            `define RM          (cmd[5:3])
            `define RDN         (cmd[2:0])
            `define LEFT        (r[`RM][4:0])
            `define RIGHT       (r[`RM][4:0] == 0 ? 32 : r[`RM][4:0])

            // BITWISE MUX
            //
            // C0 = B1 ? ~A : A
            // C1 = B0 ? 32{1} : B
            // C2 = B0 ? 32{1} : A
            // C3 = B1 ? ~B : B
            // C4 = C0 & C1 | C2 & C3
            // 
            // FUNC    EXPR                 B1  B0
            // and     A & B                0   0
            // or      A | B                0   1
            // xor     A ^ B                1   0
            // nand  ~(A & B) -> ~A | ~B    1   1
            if (`IS_TST || `IS_AND || `IS_XOR || `IS_ORR || `IS_BIC) begin
                a  = `IS_BIC ? ~r[`RM] : r[`RM];
                m0 = `IS_ORR;
                m1 = `IS_XOR;
                b  = ((m1 ? ~r[`RDN] : r[`RDN]) & (m0 ? `ALL_ONE : a)) | 
                     ((m0 ? `ALL_ONE : r[`RDN]) & (m1 ? ~a : a));

                if (`IS_NOT_TST) begin
                    r[`RDN] = b;
                end
            end else if (`IS_MUL) begin
                r[`RDN] *= r[`RM];
                b = r[`RDN];
                tmp_cf = cf; // cf 不变，所以赋值给 tmp_cf
            end else if (`IS_LSL) begin
                { tmp_cf, r[`RDN] } = { cf, r[`RDN] } << `LEFT;
                { b } = r[`RDN];
            end else if (`IS_LSR || `IS_ASR || `IS_ROR) begin
                { r[`RDN], a } = { 
                    `IS_ASR && r[`RDN][`INT_MSB] ? `ALL_ONE : `ALL_ZERO, r[`RDN], `ALL_ZERO
                } >> `RIGHT;

                { tmp_cf } = a[`INT_MSB];
                { r[`RDN] } |= `IS_ROR ? a : `ALL_ZERO;
                { b } = r[`RDN];
            // `IS_CMN || `IS_CMP || `IS_ADC || `IS_SBC || `IS_RSB || `IS_MVN
            end else begin
                { a } = `IS_MVN ? 0 : r[`RDN];
                { b, sub_cf } = `IS_SBC || `IS_CMP || `IS_MVN ? { ~a, !`IS_MVN } : { a, 1'b0 };
                { tmp_vf } = r[`RDN][`INT_MSB] == b[`INT_MSB];
                { tmp_cf, b } = a + b + sub_cf;
                { tmp_vf } = tmp_vf ? tmp_vf != b[`INT_MSB] : 0;
                { need_modify_vf } = !`IS_MVN;

                if (!(`IS_CMN || `IS_CMP)) begin
                    r[`RDN] = b;
                end
            end

            if (`IS_TST || `IS_CMN || `IS_CMP || !in_it_block) begin
                nf = b[`INT_MSB];
                zf = b == 0;
                cf = tmp_cf;

                if (need_modify_vf) begin
                    vf = tmp_vf;
                end
            end

            need_modify_vf = 0;

            `undef IS_AND
            `undef IS_XOR
            `undef IS_LSL
            `undef IS_LSR
            `undef IS_ASR
            `undef IS_ADC
            `undef IS_SBC
            `undef IS_ROR
            `undef IS_TST
            `undef IS_RSB
            `undef IS_CMP
            `undef IS_CMN
            `undef IS_ORR
            `undef IS_MUL
            `undef IS_BIC
            `undef IS_MVN
            `undef IS_NOT_TST
            `undef RM
            `undef RDN
            `undef LEFT
            `undef RIGHT
        end

        default: begin
            
        end
    endcase
end endmodule
