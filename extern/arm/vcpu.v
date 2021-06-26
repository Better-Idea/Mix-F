// 目标：低功耗设计
`timescale 1ns/1ps

`define PC              4'd15
`define REG_MSB         31
`define ALL_ONE         32'hffff_ffff
`define ALL_ZERO        32'h0000_0000
`define NOT_IN_ITB      (!in_it_block)
`define IN_ITB          (in_it_block)
`define SYS_BITS        32

module vcpu(
    input           sck,
    input [15:0]    cmd
);
    // public
    reg [31:0] r[0:15];
    reg in_it_block = 0;
    reg cf = 0;
    reg zf = 0;
    reg nf = 0;
    reg vf = 0;

    // private
    reg [31:0] a;   // adddition
    reg [31:0] b;   // temp
    reg tmp_cf = 0;
    reg tmp_zf = 0;
    reg tmp_nf = 0;
    reg tmp_vf = 0;
    reg msb_eq = 0;

    // 修改该标志位寄存器
    reg modify_state = 0;
    reg m0;
    reg m1;
always @(posedge sck) begin
    casez(cmd[15:8])
        // 移位操作
        8'b000?_????: begin
            `define MODE        (cmd[12:11])
            `define WITH_SIGN   (cmd[12])
            `define IMM5        (cmd[10:6])
            `define RM          (cmd[5:3])
            `define RD          (cmd[2:0])
            `define LEFT        (`IMM5)
            `define RIGHT       (`IMM5 == 0 ? 32 : `IMM5)

            // 逻辑右移、算数右移
            // T1:LSR RD, RM
            // T1:ASR RD, RM
            if (`MODE != 0) begin
                { r[`RD], tmp_cf } = {
                    `WITH_SIGN && r[`RM][`REG_MSB] ? `ALL_ONE : `ALL_ZERO, r[`RM], 1'b0
                } >> `RIGHT;
                { b } = r[`RD];
                { modify_state } = `NOT_IN_ITB;
                { tmp_vf } = vf;
            // T2：mov rm, rd 不允许在 IT 块中
            end else if (`IMM5 == 0 && `IN_ITB) begin
                // error
                // TODO:=============================
            // 逻辑左移、赋值
            // 当赋值的目的寄存器是 PC 寄存器时不改变状态位
            // T2: MOV RM, RD
            // T1: LSL RM, RD, IMM5
            end else begin
                { tmp_cf, r[`RD] } = { cf, r[`RM] } << `LEFT;
                { b } = r[`RD];
                { modify_state } = { `IMM5, `RD } != { 5'b0, `PC } && `NOT_IN_ITB;
                { tmp_vf } = vf;
            end

            // TODO: opcode 2'b11 invalid
            `undef MODE
            `undef WITH_SIGN
            `undef IMM5
            `undef RM
            `undef RD
            `undef LEFT
            `undef RIGHT
        end

        // 加减法
        8'b0001_1???: begin
            `define IS_IMM_RM   (cmd[10])

            // cmd[9]
            // - 0:add
            // - 1:sub
            `define IS_SUB      (cmd[9])

            `define RM          (cmd[8:6])
            `define RN          (cmd[5:3])
            `define RD          (cmd[2:0])

            // T1: ADD RD, RN, RM
            // T1: SUB RD, RN, RM
            // T1: ADD RD, RN, IMM3
            // T1: SUB RD, RN, IMM3
            { a } = `IS_IMM_RM ? `RM : r[`RM];
            { b } = `IS_SUB ? -a : a;
            { msb_eq } = r[`RN][`REG_MSB] == b[`REG_MSB];
            { tmp_cf, r[`RD] } = r[`RN] + b;
            { b } = r[`RD];
            { modify_state } = `RD != `PC && `NOT_IN_ITB;
            { tmp_vf } = msb_eq ? r[`RN][`REG_MSB] != b[`REG_MSB] : 0;

            `undef IS_IMM_RM
            `undef IS_SUB
            `undef RM
            `undef RN
            `undef RD
        end

        // 与立即数加、减、赋值、比较
        8'b001?_????: begin
            `define IS_MOV      (`MODE == 0)
            `define IS_NOT_CMP  (`MODE != 1)
            `define IS_SUB      (cmd[11])
            `define MODE        (cmd[12:11])
            `define RDN         (cmd[10:8])
            `define IMM8        (cmd[7:0])

            // T1: MOV RD, IMM8
            // T1: CMP RN, IMM8
            // T2: ADD RDN, IMM8
            // T2: SUB RDN, IMM8
            { a } = `IS_MOV ? `ALL_ZERO : r[`RDN];
            { b } = `IS_SUB ? -`IMM8 : `IMM8;
            { msb_eq } = r[`RDN][`REG_MSB] == b[`REG_MSB];
            { tmp_cf, b } = a + b;
            { modify_state } = `NOT_IN_ITB;
            { tmp_vf } = `IS_MOV ? vf : (msb_eq ? r[`RDN][`REG_MSB] != b[`REG_MSB] : 0);

            // cmp 不修改目的寄存器
            if (`IS_NOT_CMP) begin
                r[`RDN] = b;
            end

            `undef IS_MOV
            `undef IS_NOT_CMP
            `undef IS_SUB
            `undef MODE
            `undef RDN
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
            `define IS_NOT_CMP  (!`IS_CMP)
            `define IS_NOT_CMN  (!`IS_CMN)
            `define IS_NOT_MVN  (!`IS_MVN)
            `define RM          (cmd[5:3])
            `define RDN         (cmd[2:0])
            `define LEFT        (r[`RM][7:5] != 0 ? 32 : r[`RM][4:0])
            `define RIGHT       (`IS_ROR ? { 1'b0, r[`RM][4:0] } : { r[`RM][7:5] != 0, r[`RM][4:0] })

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

            // T1: AND RDN, RM
            // T1: XOR RDN, RM
            // T1: TST RDN, RM
            // T1: ORR RDN, RM
            if (`IS_AND || `IS_XOR || `IS_TST || `IS_ORR || `IS_BIC) begin
                a  = `IS_BIC ? ~r[`RM] : r[`RM];
                m0 = `IS_ORR;
                m1 = `IS_XOR;
                b  = ((m1 ? ~r[`RDN] : r[`RDN]) & (m0 ? `ALL_ONE : a)) | 
                     ((m0 ? `ALL_ONE : r[`RDN]) & (m1 ? ~a : a));

                if (`IS_NOT_TST) begin
                    r[`RDN] = b;
                end

                tmp_cf = cf;    // cf 不变
                tmp_vf = vf;    // vf 不变
                modify_state = `IS_TST || `NOT_IN_ITB;
            // T1: MUL RDN, RM
            end else if (`IS_MUL) begin
                r[`RDN] *= r[`RM];
                b = r[`RDN];
                tmp_cf = cf;    // cf 不变
                tmp_vf = vf;    // vf 不变
                modify_state = `NOT_IN_ITB;
            // T1: LSL RDN, RM
            end else if (`IS_LSL) begin
                { tmp_cf, r[`RDN] } = { cf, r[`RDN] } << `LEFT;
                { b } = r[`RDN];
                { tmp_vf } = vf;
                { modify_state } = `NOT_IN_ITB;
            end else if (`IS_LSR || `IS_ASR || `IS_ROR) begin
                { r[`RDN], a } = { 
                    `IS_ASR && r[`RDN][`REG_MSB] ? `ALL_ONE : `ALL_ZERO, r[`RDN], `ALL_ZERO
                } >> `RIGHT;

                { r[`RDN] } |= `IS_ROR ? a : `ALL_ZERO;
                { b } = r[`RDN];
                { tmp_cf } = a[`REG_MSB];
                { tmp_vf } = vf;
                { modify_state } = `NOT_IN_ITB;
            // `IS_CMN || `IS_CMP || `IS_ADC || `IS_SBC || `IS_RSB || `IS_MVN
            end else begin
                { a } = `IS_MVN ? 0 : r[`RDN];
                { b } = `IS_SBC || `IS_CMP || `IS_MVN ? ~a  + `IS_NOT_MVN : a;
                { msb_eq } = r[`RDN][`REG_MSB] == b[`REG_MSB];
                { tmp_cf, b } = a + b;
                { tmp_vf } = `IS_MVN ? vf : (msb_eq ? r[`RDN][`REG_MSB] != b[`REG_MSB] : 0);
                { modify_state } = `NOT_IN_ITB || `IS_CMN || `IS_CMP;

                if (`IS_NOT_CMN && `IS_NOT_CMP) begin
                    r[`RDN] = b;
                end
            end

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
            `undef IS_NOT_CMP
            `undef IS_NOT_CMN
            `undef IS_NOT_MVN
            `undef RM
            `undef RDN
            `undef LEFT
            `undef RIGHT
        end

        default: begin
            
        end
    endcase

    if (modify_state) begin
        modify_state = 0;
        nf = b[`REG_MSB];
        zf = b == 0;
        cf = tmp_cf;
        vf = tmp_vf;
    end

end endmodule
