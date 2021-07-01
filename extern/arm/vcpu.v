// 目标：低功耗设计
`timescale 1ns/1ps

`define PC                  4'd15
`define LR                  4'd14
`define REG_MSB             31
`define ALL_ONE             32'hffff_ffff
`define ALL_ZERO            32'h0000_0000
`define NOT_IN_ITB          (!in_it_block)
`define NOT_LAST_IN_ITB     (!last_in_it_block)
`define SYS_BITS            32
`define SYS_BITS_PLUS1      6'd33
`define SYS_BITS_SUB3       29
`define SYS_BITS_SUB8       24
`define SYS_BITS_SUB16      16
`define SYS_BITS_SUB8       24

// 修改一个寄存器的放在低组
`define B_LOW               0
`define I_SHIFT             0
`define I_ADD               1
`define I_MUL               2
`define I_BITWISE           3
`define I_MEM               4

// 修改 2 个寄存器的放在高组
`define B_HIG               10
`define I_BL                10

`define I_MAX               15 /*当 I_MAX 需要变大时需要修改下方 d 的元素个数*/

module vcpu(
    input           sck,
    input  [15:0]   cmd,
    output [31:0]   opt,
    output [31:0]   sta
);

// public
reg [31:0] r[0:15];
reg in_it_block = 0;
reg last_in_it_block = 0;
reg cf = 0;
reg zf = 0;
reg nf = 0;
reg vf = 0;

// private
wire[31:0] d[`B_LOW:`I_MAX];    // 目的寄存器
wire[31:0] e[`B_HIG:`I_MAX];    // 目的寄存器
wire[15:0] tmp_cf;
wire[15:0] tmp_vf;
wire[15:0] msb_eq;
reg [ 4:0] reg_ds;
reg [ 4:0] reg_es;
reg [31:0] n;                   // d = n op m
reg [31:0] m;

reg [31:0] tmp_ds_shift  ;
reg [31:0] tmp_ds_add    ;
reg [31:0] tmp_ds_mul    ;
reg [31:0] tmp_ds_bitwise;
reg [31:0] tmp_ds_mem    ;
reg [31:0] tmp_ds_bl     ;

reg [31:0] tmp_es_bl;

reg tmp_cf_shift  , tmp_vf_shift  , msb_eq_shift  , tmp_zf_shift  , tmp_of_shift  ;
reg tmp_cf_add    , tmp_vf_add    , msb_eq_add    , tmp_zf_add    , tmp_of_add    ;
reg tmp_cf_mul    , tmp_vf_mul    , msb_eq_mul    , tmp_zf_mul    , tmp_of_mul    ;
reg tmp_cf_bitwise, tmp_vf_bitwise, msb_eq_bitwise, tmp_zf_bitwise, tmp_of_bitwise;
reg tmp_cf_bl     , tmp_vf_bl     , msb_eq_bl     , tmp_zf_bl     , tmp_of_bl     ;
reg tmp_cf_mem    , tmp_vf_mem    , msb_eq_mem    , tmp_zf_mem    , tmp_of_mem    ;

// 修改该标志位寄存器
reg modify_state_req = 0;
reg modify_state_ack = 0;

// i_serial 最大值不能超过 d 数组的索引
reg [ 3:0] i_serial = 0;

assign opt = d[i_serial];
assign sta[31] = nf;
assign sta[30] = zf;
assign sta[29] = cf;
assign sta[28] = vf;

assign d     [`I_SHIFT  ] = tmp_ds_shift  ;
assign d     [`I_ADD    ] = tmp_ds_add    ;
assign d     [`I_MUL    ] = tmp_ds_mul    ;
assign d     [`I_BITWISE] = tmp_ds_bitwise;
assign d     [`I_MEM    ] = tmp_ds_mem    ;
assign d     [`I_BL     ] = tmp_ds_bl     ;
assign e     [`I_BL     ] = tmp_es_bl     ;

assign tmp_cf[`I_SHIFT  ] = tmp_cf_shift  , tmp_vf[`I_SHIFT  ] = tmp_vf_shift  , msb_eq[`I_SHIFT  ] = msb_eq_shift  ;
assign tmp_cf[`I_ADD    ] = tmp_cf_add    , tmp_vf[`I_ADD    ] = tmp_vf_add    , msb_eq[`I_ADD    ] = msb_eq_add    ;
assign tmp_cf[`I_MUL    ] = tmp_cf_mul    , tmp_vf[`I_MUL    ] = tmp_vf_mul    , msb_eq[`I_MUL    ] = msb_eq_mul    ;
assign tmp_cf[`I_BITWISE] = tmp_cf_bitwise, tmp_vf[`I_BITWISE] = tmp_vf_bitwise, msb_eq[`I_BITWISE] = msb_eq_bitwise;
assign tmp_cf[`I_BL     ] = tmp_cf_bl     , tmp_vf[`I_BL     ] = tmp_vf_bl     , msb_eq[`I_BL     ] = msb_eq_bl     ;

`define CAN_WRITE_DS        reg_ds[4] == 0
`define CAN_WRITE_ES        reg_es[4] == 0
`define NOT_WRITE_DS        5'h1f
`define NOT_WRITE_ES        5'h1f
`define REG_DS              r[reg_ds[3:0]]
`define REG_ES              r[reg_es[3:0]]

`define CUR_TMP_CF          tmp_cf[i_serial]
`define CUR_TMP_VF          tmp_vf[i_serial]
`define CUR_MSB_EQ          msb_eq[i_serial]
`define CUR_TMP_DS          d[i_serial]
`define CUR_TMP_ES          e[i_serial]

// 移位操作 ========================================
`define SHIFT_LEFT          1'b0
`define SHIFT_RIGHT         1'b1

reg [31:0]  shift_temp      = 0;
reg [5:0]   shift_bits      = 0;
reg         shift_direction = 0;    // 0 : left / 1 : right
reg         shift_with_sign = 0;    // 带符号移位，只对右移有效
reg         shift_with_loop = 0;    // 循环移位，只对右移有效
reg         shift_req       = 0;
reg         shift_ack       = 0;

always @(posedge (shift_req != shift_ack)) begin
    shift_bits = m[7:0] > `SYS_BITS ? `SYS_BITS_PLUS1 : m[5:0];

    if (shift_direction == `SHIFT_LEFT) begin // 左移
        { tmp_cf_shift, tmp_ds_shift } = { cf, n } << shift_bits;
    end else begin // 右移
        { tmp_ds_shift, shift_temp } = {
            { `SYS_BITS_PLUS1{ shift_with_sign && n[`REG_MSB] } }, n, `ALL_ZERO
        } >> (shift_with_loop ? { 1'b0, m[4:0] } : { shift_bits });

        { tmp_ds_shift } = shift_temp[`REG_MSB];

        if (shift_with_loop) begin
            tmp_ds_shift = tmp_ds_shift | shift_temp;
        end
    end

    // 不更改 vf
    { tmp_vf_shift } = vf;
    { shift_ack } = shift_req;
end

// 加法操作 ========================================
reg add_with_cf             = 0;
reg add_req                 = 0;
reg add_ack                 = 0;

always @(posedge (add_req != add_ack)) begin
    { msb_eq_add } = n[`REG_MSB] == m[`REG_MSB];
    { tmp_cf_add, tmp_ds_add } = n + m + add_with_cf;
    { tmp_vf_add } = msb_eq_add ? n[`REG_MSB] != tmp_ds_add[`REG_MSB] : 0;
    { add_ack } = add_req;
end

// 乘法操作 ========================================
reg mul_req                 = 0;
reg mul_ack                 = 0;

always @(posedge (mul_req != mul_ack)) begin
    { tmp_ds_mul } = n * m;
    { tmp_cf_mul } = cf;
    { tmp_vf_mul } = vf;
    { mul_ack } = mul_req;
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
reg bitwise_m0              = 0;
reg bitwise_m1              = 0;
reg bitwise_req             = 0;
reg bitwise_ack             = 0;

always @(posedge (bitwise_req != bitwise_ack)) begin
    { tmp_ds_bitwise } =
        ((bitwise_m1 ? ~n       : n) & (bitwise_m0 ? `ALL_ONE : m)) | 
        ((bitwise_m0 ? `ALL_ONE : n) & (bitwise_m1 ? ~m       : m));
    { tmp_vf_bitwise } = vf;
    { bitwise_ack } = bitwise_req;
end

// 转移指令
reg bl_req                  = 0;
reg bl_ack                  = 0;
reg bl_with_link            = 0;

always @(posedge (bl_req != bl_ack)) begin
    if (bl_with_link) begin
        { tmp_es_bl } = r[`PC] + 3/*2 + 1*/;
    end

    { tmp_ds_bl } = m;
    { bl_ack } = bl_req;
end

// 内存加载指令
reg mem_req                 = 0;
reg mem_ack                 = 0;
reg mem_mode                = 0;
reg mem_is_signed           = 0;
reg [ 1:0] mem_scale        = 0;
reg [31:0] mem_addr         = 0;

`define MEM_MODE_READ       1'b0
`define MEM_MODE_WRITE      1'b1
`define MEM_SCALE_8BIT      2'b00
`define MEM_SCALE_16BIT     2'b01
`define MEM_SCALE_32BIT     2'b10

always @(posedge (mem_req != mem_ack)) begin
    { mem_addr } = n + m;
    { tmp_ds_mem } = mem_addr; // TODO：内存访问模块

    if (mem_is_signed && mem_mode == `MEM_MODE_READ) begin
        casez(mem_scale)
        `MEM_SCALE_8BIT : begin
            tmp_ds_mem = { { `SYS_BITS_SUB8 {tmp_ds_mem[ 7]} }, tmp_ds_mem[ 7:0] };
        end
        `MEM_SCALE_16BIT: begin
            tmp_ds_mem = { { `SYS_BITS_SUB16{tmp_ds_mem[15]} }, tmp_ds_mem[15:0] };
        end
        endcase
    end

    { mem_ack } = !mem_req;
end

always @(posedge sck) begin
    // 大部分指令只有一个目的寄存器
    // 一般只要写入 DS 对应的寄存器就好了
    { reg_ds } = `NOT_WRITE_DS;
    { reg_es } = `NOT_WRITE_ES;

    casez(cmd[15:8])
        // 移位操作
        // mov PC, #imm 不更改状态位
        8'b000?_????: begin
            { i_serial } = `I_SHIFT;
            { reg_ds } = cmd[2:0];  // RD
            { n } = r[cmd[5:3]];    // RN
            { m } = cmd[10:6];      // IMM5
            { shift_direction } = cmd[12:11] ? `SHIFT_RIGHT : `SHIFT_LEFT;
            { shift_with_sign } = cmd[12];
            { modify_state_req } = 
                `NOT_IN_ITB && !(cmd[12:11] == 0 && cmd[10:6] == 0 && reg_ds == `PC) ?
                !modify_state_ack : modify_state_ack;
            { shift_req } = !shift_ack;
        end

        // 加减法
        8'b0001_1???: begin
            `define IS_IMM      (cmd[10])
            `define IS_NOT_IMM  (cmd[10] == 0)

            // cmd[9]
            // - 0:add
            // - 1:sub
            `define IS_NEG      (cmd[9])

            { i_serial } = `I_ADD;
            { reg_ds } = cmd[2:0];
            { n } =  r[cmd[5:3]];
            { m, add_with_cf } = 
                { `IS_IMM ? { { `SYS_BITS_SUB3{!`IS_IMM/*0*/} }, cmd[8:6], 1'b0 } : { r[cmd[8:6]], 1'b0 } } ^ 
                { `SYS_BITS_PLUS1{`IS_NEG} };
            { modify_state_req } = `NOT_IN_ITB ? !modify_state_ack : modify_state_ack;
            { add_req } = !add_ack;
        end

        // 与立即数加、减、赋值、比较
        8'b001?_????: begin
            `define IS_MOV      (`MODE == 0)
            `define IS_CMP      (`MODE == 1)
            `define IS_NEG      (cmd[11])
            `define MODE        (cmd[12:11])
            `define RD          (cmd[10:8])
            `define RN          (cmd[10:8])
            `define IMM8        (cmd[7:0])

            { i_serial } = `I_ADD;
            { reg_ds } = `IS_CMP ? `NOT_WRITE_DS : `RD;
            { n } = `IS_MOV ? `ALL_ZERO : r[`RN];
            { m, add_with_cf } = { {`SYS_BITS_SUB8{`IS_NEG}}, `IMM8 ^ {8{`IS_NEG}}, `IS_NEG };
            { modify_state_req } = `NOT_IN_ITB ? !modify_state_ack : modify_state_ack;
            { add_req } = !add_ack;
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
            `define RD          (cmd[2:0])
            `define RN          (cmd[2:0])
            `define RM          (cmd[5:3])

            if (`IS_AND || `IS_XOR || `IS_TST || `IS_ORR || `IS_BIC) begin
                { i_serial } = `I_BITWISE;
                { reg_ds } = `IS_TST ? `NOT_WRITE_DS : `RD;
                { n } = r[`RN];
                { m } = `IS_BIC ? ~r[`RM] : r[`RM];
                { modify_state_req } = `NOT_IN_ITB  ? !modify_state_ack : modify_state_ack;
                { bitwise_req } = !bitwise_ack;
            end else if (`IS_MUL) begin
                { i_serial } = `I_MUL;
                { reg_ds } = `RD;
                { n } = r[`RN];
                { m } = r[`RM];
                { modify_state_req } = `NOT_IN_ITB  ? !modify_state_ack : modify_state_ack;
                { mul_req } = !mul_ack;
            end else if (`IS_LSL || `IS_LSR || `IS_ASR || `IS_ROR) begin
                { i_serial } = `I_SHIFT;
                { reg_ds } = `RD;
                { n } = r[`RN];
                { m } = r[`RM];
                { shift_direction } = `IS_LSL ? `SHIFT_LEFT : `SHIFT_RIGHT;
                { shift_with_sign } = `IS_ASR;
                { shift_with_loop } = `IS_ROR;
                { modify_state_req } = `NOT_IN_ITB ? !modify_state_ack : modify_state_ack;
                { shift_req } = !shift_ack;
            // `IS_CMN || `IS_CMP || `IS_ADC || `IS_SBC || `IS_RSB || `IS_MVN
            end else begin
                { i_serial } = `I_ADD;
                { reg_ds } = `IS_CMN || `IS_CMP ? `NOT_WRITE_DS : `RD;
                { n } = `IS_MVN ? `ALL_ZERO : r[`RN];
                { m } = r[`RM] ^ { `SYS_BITS{ `IS_SBC || `IS_CMP || `IS_MVN } };
                { add_with_cf } = `IS_CMP || ((`IS_ADC | `IS_SBC/*thumb 奇怪的定义*/) && cf);
                { modify_state_req } = `NOT_IN_ITB ? !modify_state_ack : modify_state_ack;
                { add_req } = !add_ack;

                // 关于 SBC
                // d = n - m - !cf
                // d = n + ~m + (1 - !cf)
                // d = n + ~m + cf
            end
        end

        // ADD/CMP/MOV
        8'b0100_01??: begin
            `define MODE        (cmd[9:8])
            `define RD          {cmd[7], cmd[2:0]}
            `define RN          {cmd[7], cmd[2:0]}
            `define RM          (cmd[6:3])
            `define IS_CMP      (`MODE == 1)
            `define IS_MOV      (`MODE == 2)

            { i_serial } = `I_ADD;
            { reg_ds } = `IS_CMP ? `NOT_WRITE_DS : `RD;
            { n } = `IS_MOV ? `ALL_ZERO : r[`RN];
            { m } = r[`RM] ^ { `SYS_BITS{`IS_CMP} };
            { add_with_cf } = `IS_CMP;
            { modify_state_req } = `NOT_IN_ITB && `RD != `PC ? 
                !modify_state_ack : modify_state_ack;
            { add_req } = !add_ack;
        end

        // 转移
        8'b0100_0111: begin
            `define LINK        (cmd[7])
            `define RM          (cmd[6:3])
            `define ZERO        (cmd[2:0])

            if (`ZERO == 0 && 
                `NOT_IN_ITB && 
                `NOT_LAST_IN_ITB && 
                !(`LINK && `RM == `PC)
            ) begin
                { i_serial } = `I_BL;
                { m } = r[`RM];
                { bl_req } = !bl_ack;
            end else begin
                // ERROR
            end
        end

        // load from literal pool
        8'b0100_1???: begin
            { i_serial } = `I_MEM;
            { mem_mode } = `MEM_MODE_READ;
            { mem_scale } = `MEM_SCALE_32BIT;
            { mem_is_signed } = 0;
            { reg_ds } = cmd[10:8];
            // 确认一下 PC 是否需要对齐
            { n } = r[`PC];
            { m } = { cmd[7:0], 2'b0 };
            { mem_req } = !mem_ack;
        end

        // load/store register offset
        8'b0101_????: begin
            
        end

        // load/store word/byte immediate offset

        default: begin
            
        end
    endcase
end

always @(negedge sck) begin
    if (modify_state_req != modify_state_ack) begin
        modify_state_ack = modify_state_req;
        nf = `CUR_TMP_DS[`REG_MSB];
        zf = `CUR_TMP_DS == 0;
        cf = `CUR_TMP_CF;
        vf = `CUR_TMP_VF;
    end

    if (`CAN_WRITE_DS) begin
        `REG_DS = `CUR_TMP_DS;
    end

    if (`CAN_WRITE_ES) begin
        `REG_ES = `CUR_TMP_ES;
    end
end endmodule
