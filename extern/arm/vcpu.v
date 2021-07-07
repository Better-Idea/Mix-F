// 目标：低功耗设计
`timescale 1ns/1ps

`define SP                  4'd13
`define LR                  4'd14
`define PC                  4'd15
`define REG_MSB             31
`define ALL_ONE             32'hffff_ffff
`define ALL_ZERO            32'h0000_0000
`define IN_ITB              (in_it_block)
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
    input           rst,
    input           sck,
    input  [15:0]   cmd,
    output [31:0]   opt,
    output [31:0]   sta
);

dist_mem_gen_0 rom(
    .a(cmd[9:0]),
    .spo(opt)
);

// public
reg [31:0] r[0:15];
reg [31:0] base_svc_table;
reg in_it_block;
reg last_in_it_block;
reg cf;
reg zf;
reg nf;
reg vf;
reg tmp_make_jmp;
reg tmp_error;

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
// reg tmp_cf_mem    , tmp_vf_mem    , msb_eq_mem    , tmp_zf_mem    , tmp_of_mem    ;

// 修改该标志位寄存器
reg modify_state_req = 0;
reg modify_state_ack = 0;

// i_serial 最大值不能超过 d 数组的索引
reg [ 3:0] i_serial = 0;

// assign opt      = d[i_serial];
assign sta[31]  = nf;
assign sta[30]  = zf;
assign sta[29]  = cf;
assign sta[28]  = vf;

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

reg [31:0]  shift_temp;
reg [5:0]   shift_bits;
reg         shift_direction;    // 0 : left / 1 : right
reg         shift_with_sign;    // 带符号移位，只对右移有效
reg         shift_with_loop;    // 循环移位，只对右移有效
reg         shift_req;
reg         shift_ack;

always @(posedge (shift_req != shift_ack) or posedge rst) begin
    if (rst) begin
        { shift_temp } = 0;
        { shift_bits } = 0;
        { shift_ack } = 0;
    end else begin
        { shift_bits } = m[7:0] > `SYS_BITS ? `SYS_BITS_PLUS1 : m[5:0];

        if (shift_direction == `SHIFT_LEFT) begin // 左移
            { tmp_cf_shift, tmp_ds_shift } = { cf, n } << shift_bits;
        end else begin // 右移
            { tmp_ds_shift, shift_temp } = {
                { `SYS_BITS_PLUS1{ shift_with_sign && n[`REG_MSB] } }, n, `ALL_ZERO
            } >> (shift_with_loop ? { 1'b0, m[4:0] } : { shift_bits });

            { tmp_ds_shift } = shift_temp[`REG_MSB];

            if (shift_with_loop) begin
                { tmp_ds_shift } = tmp_ds_shift | shift_temp;
            end
        end

        // 不更改 vf
        { tmp_vf_shift } = vf;
        { shift_ack } = shift_req;
    end
end

// 加法操作 ========================================
reg add_with_cf;
reg add_req;
reg add_ack;

always @(posedge (add_req != add_ack) or posedge rst) begin
    if (rst) begin
        { add_ack } = 0;
    end else begin
        { msb_eq_add } = n[`REG_MSB] == m[`REG_MSB];
        { tmp_cf_add, tmp_ds_add } = n + m + add_with_cf;
        { tmp_vf_add } = msb_eq_add ? n[`REG_MSB] != tmp_ds_add[`REG_MSB] : 0;
        { add_ack } = add_req;
    end
end

// 乘法操作 ========================================
reg mul_req;
reg mul_ack;

always @(posedge (mul_req != mul_ack) or posedge rst) begin
    if (rst) begin
        { mul_ack } = 0;
    end else begin
        { tmp_ds_mul } = n * m;
        { tmp_cf_mul } = cf;
        { tmp_vf_mul } = vf;
        { mul_ack } = mul_req;
    end
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
reg bitwise_m0;
reg bitwise_m1;
reg bitwise_req;
reg bitwise_ack;

always @(posedge (bitwise_req != bitwise_ack) or posedge rst) begin
    if (rst) begin
        { bitwise_ack } = 0;
    end else begin
        { tmp_ds_bitwise } =
            ((bitwise_m1 ? ~n       : n) & (bitwise_m0 ? `ALL_ONE : m)) | 
            ((bitwise_m0 ? `ALL_ONE : n) & (bitwise_m1 ? ~m       : m));
        { tmp_vf_bitwise } = vf;
        { bitwise_ack } = bitwise_req;
    end
end

// 转移指令
reg bl_req;
reg bl_ack;
reg bl_with_link;

always @(posedge (bl_req != bl_ack) or posedge rst) begin
    if (rst) begin
        { bl_ack } = 0;
    end else begin
        if (bl_with_link) begin
            { tmp_es_bl } = r[`PC] + 3/*2 + 1*/;
        end

        { tmp_ds_bl } = m;
        { bl_ack } = bl_req;
    end
end

// 内存加载指令
reg mem_req                 = 0;
reg mem_ack                 = 0;
reg mem_mode                = 0;
reg mem_is_signed           = 0;
reg mem_continue            = 0;
reg [ 4:0] mem_buffer_i[0:7];
reg [ 4:0] mem_i            = 0;
reg [ 4:0] mem_end          = 0;
reg [ 1:0] mem_scale        = 0;
reg [31:0] mem_addr         = 0;

// 和指令编码保持一致，load/store register offset 依赖此顺序
`define MEM_MODE_WRITE      1'b0
`define MEM_MODE_READ       1'b1

// 和指令编码保持一致，load/store register offset 依赖此顺序
`define MEM_SCALE_8BIT      2'b10
`define MEM_SCALE_16BIT     2'b01
`define MEM_SCALE_32BIT     2'b00

always @(posedge (mem_req != mem_ack) or posedge rst) begin
    if (rst) begin
        { mem_ack } = 0;
        { mem_addr } = 0;
    end else begin
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

        { mem_ack } = mem_req;
    end
end

always @(posedge sck or posedge rst) begin
    // 大部分指令只有一个目的寄存器
    // 一般只要写入 DS 对应的寄存器就好了
    { reg_ds } = `NOT_WRITE_DS;
    { reg_es } = `NOT_WRITE_ES;

    if (rst) begin
        { base_svc_table } = 0;
        { in_it_block } = 0;
        { last_in_it_block } = 0;

        { shift_direction } = 0;
        { shift_with_sign } = 0;
        { shift_with_loop } = 0;
        { shift_req } = 0;

        { add_with_cf } = 0;

        { mul_req } = 0;

        { bitwise_m0 } = 0;
        { bitwise_m1 } = 0;
        { bitwise_req } = 0;

        { bl_req } = 0;
        { bl_with_link } = 0;

        { mem_req } = 0;
        { mem_mode } = 0;
        { mem_is_signed } = 0;
        { mem_continue } = 0;
        { mem_buffer_i[0] } = 0;
        { mem_buffer_i[1] } = 0;
        { mem_buffer_i[2] } = 0;
        { mem_buffer_i[3] } = 0;
        { mem_buffer_i[4] } = 0;
        { mem_buffer_i[5] } = 0;
        { mem_buffer_i[6] } = 0;
        { mem_buffer_i[7] } = 0;
        { mem_i } = 0;
        { mem_end } = 0;
        { mem_scale } = 0;
    end else if (mem_continue) begin
        { mem_i } = mem_i + 1;
        { reg_ds } = mem_buffer_i[mem_i];
        { m } = { mem_i, 2'b0 };
        { mem_continue } = mem_i != mem_end;
    end else casez(cmd[15:8])
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
            `define RN          (cmd[10:8])
            `define RD          (cmd[10:8])
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
            `define RM          (cmd[5:3])
            `define RN          (cmd[2:0])
            `define RD          (cmd[2:0])

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
            `define RM          (cmd[6:3])
            `define RN          {cmd[7], cmd[2:0]}
            `define RD          {cmd[7], cmd[2:0]}
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

        // Load from literal pool
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

        // Load/store register offset
        8'b0101_????: begin
            `define MODE            (cmd[11:9])
            `define SCALE           (cmd[10:9])
            `define IS_SIGNED       (cmd[10:9] == 2'b11)
            `define SIGNED_SCALE    {!cmd[11], cmd[11]}
            `define RM              (cmd[ 8:6])
            `define RN              (cmd[ 5:3])
            `define RD              (cmd[ 2:0])

            { i_serial } = `I_MEM;
            
            // 000: 32bit store
            // 001: 16bit store
            // 010: 08bit store
            if (`MODE < 3) begin
                { mem_mode } = `MEM_MODE_WRITE;
                { mem_scale } = `SCALE;
                { mem_is_signed } = 0;
            // 011: 08bit load with sign
            // 100: 32bit load
            // 101: 16bit load
            // 110: 08bit load
            // 111: 16bit load with sign
            end else begin
                { mem_mode } = `MEM_MODE_READ;
                { mem_scale } = `IS_SIGNED ? `SIGNED_SCALE : `SCALE;
                { mem_is_signed } = `IS_SIGNED;
            end

            { reg_ds } = `RD;
            { n } = r[`RN];
            { m } = r[`RM];
            { mem_req } = !mem_ack;
        end

        // 8'b011?_????: Load/store word/byte immediate offset
        // 8'b1000_????: Load/store halfword immediate offset
        8'b011?_????, 8'b1000_????: begin
            `define B               (cmd[12])
            `define L               (cmd[11])
            `define IMM5            (cmd[10:6])
            `define RN              (cmd[5:3])
            `define RD              (cmd[2:0])

            { i_serial } = `I_MEM;

            // 0:store  -> 0:MEM_MODE_WRITE
            // 1:load   -> 1:MEM_MODE_READ
            { mem_mode } = `L;

            // 00:32bit `B = 0
            // 01:16bit `B = 0
            // 10:08bit `B = 1
            { mem_scale } = { `B, cmd[15] };
            { mem_is_signed } = 0;

            { reg_ds } = `RD;
            { n } = r[`RN];
            { m } = `IMM5;
            { mem_req } = !mem_ack;
        end

        // Load from stack and store to stack instructions
        8'b1001_????: begin
            `define L               (cmd[11])
            `define RD              (cmd[10:8])
            `define IMM8            (cmd[7:0])

            { i_serial } = `I_MEM;
            { mem_mode } = `L;
            { mem_scale } = `MEM_SCALE_32BIT;
            { mem_is_signed } = 0;
            { reg_ds } = `RD;
            { n } = r[`SP];
            { m } = { `IMM8, 2'b0 };
            { mem_req } = !mem_ack;
        end

        // Add 8-bit immediate to SP or PC instructions
        8'b1010_????: begin
            `define IS_SP           (cmd[11])
            `define IS_SET_FLAG     (cmd[11])
            `define RD              (cmd[10:8])
            `define IMM8            (cmd[7:0])

            { i_serial } = `I_ADD;
            { reg_ds } = `RD;
            { n } = r[`IS_SP ? `SP : `PC];
            { m } = { `IMM8, 2'b0 };
            { add_with_cf } = 0;
            { modify_state_req } = `IS_SET_FLAG ^ modify_state_req;
            { add_req } = !add_ack;
        end

        // Miscellaneous instruction
        // TODO:================================================================
        8'b1011_????: begin
            casez (cmd[11:8])
            // Adjust stack pointer
            4'b0000: begin
                `define IS_SUB      (cmd[7])
                `define IMM7        (cmd[6:0])

                { i_serial } = `I_ADD;
                { reg_ds } = `SP;
                { n } = r[`SP];
                { m } = { `IMM7, 2'b0 } ^ { `SYS_BITS{ `IS_SUB } };
                { add_with_cf } = `IS_SUB;
                // { modify_state_req } = modify_state_req; // 不改变状态位
                { add_req } = !add_ack;
            end

            //  Sign or zero extend instructions
            4'b0010: begin
                `define RD          (cmd[2:0])
                `define RM          (cmd[5:3])
                `define SIGN_EXTERN (cmd[7])
                `define IS_BYTE     (cmd[6])

                { i_serial } = `I_BITWISE;
                { reg_ds } = `RD;
                { n } = r[`RM][15:0] & { {8{ !`IS_BYTE }} , 8'hff };
                { m } = { `SYS_BITS{ `SIGN_EXTERN & r[`RM][`IS_BYTE ? 7 : 15] }} << { `IS_BYTE ? 8 : 16 };
                { bitwise_req } = !bitwise_ack;
            end

            default: begin
                
            end
            endcase 
        end

        // Load and store multiple
        8'b1100_????: begin
            `define L               (cmd[11])
            `define RN              (cmd[10:8])
            `define BMP_REG_LIST    (cmd[7:0])

            // error
            if (`BMP_REG_LIST == 0) begin
            end else begin
                casez (cmd[3:0])
                4'b0001: begin mem_buffer_i[0] = 0; mem_end = 1; end
                4'b0010: begin mem_buffer_i[0] = 1; mem_end = 1; end
                4'b0011: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 1; mem_end = 2; end
                4'b0100: begin mem_buffer_i[0] = 2; mem_end = 1; end
                4'b0101: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 2; mem_end = 2; end
                4'b0110: begin mem_buffer_i[0] = 1; mem_buffer_i[1] = 2; mem_end = 2; end
                4'b0111: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 1; mem_buffer_i[2] = 2; mem_end = 3; end
                4'b1000: begin mem_buffer_i[0] = 3; mem_end = 1; end
                4'b1001: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 3; mem_end = 2; end
                4'b1010: begin mem_buffer_i[0] = 1; mem_buffer_i[1] = 3; mem_end = 2;  end
                4'b1011: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 1; mem_buffer_i[2] = 3; mem_end = 3; end
                4'b1100: begin mem_buffer_i[0] = 2; mem_buffer_i[1] = 3; mem_end = 2;  end
                4'b1101: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 2; mem_buffer_i[2] = 3; mem_end = 3; end
                4'b1110: begin mem_buffer_i[0] = 1; mem_buffer_i[1] = 2; mem_buffer_i[2] = 3; mem_end = 3; end
                4'b1111: begin mem_buffer_i[0] = 0; mem_buffer_i[1] = 1; mem_buffer_i[2] = 2; mem_buffer_i[3] = 3; mem_end = 4; end
                default: begin mem_end = 0; end
                endcase

                casez (cmd[7:4])
                4'b0001: begin mem_buffer_i[mem_end + 0] = 0; mem_end = mem_end + 1; end
                4'b0010: begin mem_buffer_i[mem_end + 0] = 1; mem_end = mem_end + 1; end
                4'b0011: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 1; mem_end = mem_end + 2; end
                4'b0100: begin mem_buffer_i[mem_end + 0] = 2; mem_end = mem_end + 1; end
                4'b0101: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 2; mem_end = mem_end + 2; end
                4'b0110: begin mem_buffer_i[mem_end + 0] = 1; mem_buffer_i[mem_end + 1] = 2; mem_end = mem_end + 2; end
                4'b0111: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 1; mem_buffer_i[mem_end + 2] = 2; mem_end = mem_end + 3; end
                4'b1000: begin mem_buffer_i[mem_end + 0] = 3; mem_end = mem_end + 1; end
                4'b1001: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 3; mem_end = mem_end + 2; end
                4'b1010: begin mem_buffer_i[mem_end + 0] = 1; mem_buffer_i[mem_end + 1] = 3; mem_end = mem_end + 2;  end
                4'b1011: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 1; mem_buffer_i[mem_end + 2] = 3; mem_end = mem_end + 3; end
                4'b1100: begin mem_buffer_i[mem_end + 0] = 2; mem_buffer_i[mem_end + 1] = 3; mem_end = mem_end + 2;  end
                4'b1101: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 2; mem_buffer_i[mem_end + 2] = 3; mem_end = mem_end + 3; end
                4'b1110: begin mem_buffer_i[mem_end + 0] = 1; mem_buffer_i[mem_end + 1] = 2; mem_buffer_i[mem_end + 2] = 3; mem_end = mem_end + 3; end
                4'b1111: begin mem_buffer_i[mem_end + 0] = 0; mem_buffer_i[mem_end + 1] = 1; mem_buffer_i[mem_end + 2] = 2; mem_buffer_i[mem_end + 3] = 3; mem_end = mem_end + 4; end
                default: begin end
                endcase

                { i_serial } = `I_MEM;
                { mem_mode } = `L;
                { mem_scale } = `MEM_SCALE_32BIT;
                { mem_is_signed } = 0;
                { reg_ds } = mem_buffer_i[0];
                { mem_i } = 1;
                { mem_continue } = mem_i != mem_end;
                { mem_req } = !mem_ack;
            end
        end

        // Jump
        8'b1101_????: begin
            `define EQ          (3'b000)
            `define CF          (3'b001)
            `define NF          (3'b010)
            `define VF          (3'b011)
            `define CFZ         (3'b100)
            `define GE          (3'b101)
            `define GT          (3'b110)
            `define NOT         (cmd[8])
            `define LIMIT       (cmd[8] == 0)
            `define IMM8        (cmd[7:0])
            `define SVC         (4'b1111)

            if (cmd[11:8] == `SVC) begin
                { i_serial } = `I_MEM;
                { mem_mode } = `MEM_MODE_READ;
                { mem_scale } = `MEM_SCALE_32BIT;
                { mem_is_signed } = 0;
                { reg_ds } = `PC;
                { n } = base_svc_table;
                { m } = { `IMM8, 2'b0 }; // TODO:确认中断流程===========================
                { mem_req } = !mem_ack;
            end else begin
                { i_serial } = `I_ADD;
                { reg_ds } = `PC;
                { n } = r[`PC];
                { m } = `IMM8;
                { add_with_cf } = 0;

                casez(cmd[11:9])
                `EQ :    begin tmp_make_jmp = (`NOT) ^ zf; end
                `CF :    begin tmp_make_jmp = (`NOT) ^ cf; end
                `NF :    begin tmp_make_jmp = (`NOT) ^ nf; end
                `VF :    begin tmp_make_jmp = (`NOT) ^ vf; end
                `CFZ:    begin tmp_make_jmp = (`NOT ^ !zf) & cf; end
                `GE :    begin tmp_make_jmp = (`NOT) ^ (nf == vf); end
                `GT :    begin tmp_make_jmp = (`NOT) ^ ((!zf & nf & vf) | (!nf & !vf)); end
                // Undefined instruction
                default: begin tmp_make_jmp = 0; tmp_error = 1; end
                endcase

                { add_req } = tmp_make_jmp ^ add_ack;
            end
        end

        8'b1110_0???: begin
            `define IMM11       (cmd[10:0])

            { i_serial } = `I_ADD;
            { reg_ds } = `PC;
            { n } = r[`PC];
            { m } = `IMM11;
            { add_with_cf } = 0;
            { add_req } = !add_ack;
        end

        // 32bit instruction
        8'b1110_1???: begin
            
        end

        // 32bit instruction
        8'b1111_????: begin
            
        end

        default: begin
            
        end
    endcase
end

always @(negedge sck or posedge rst) begin
    if (rst) begin
        { r[4'h0] } = 0;
        { r[4'h1] } = 0;
        { r[4'h2] } = 0;
        { r[4'h3] } = 0;
        { r[4'h4] } = 0;
        { r[4'h5] } = 0;
        { r[4'h6] } = 0;
        { r[4'h7] } = 0;
        { r[4'h8] } = 0;
        { r[4'h9] } = 0;
        { r[4'ha] } = 0;
        { r[4'hb] } = 0;
        { r[4'hc] } = 0;
        { r[4'hd] } = 0;
        { r[4'he] } = 0;
        { r[4'hf] } = 0;
        { cf, zf, nf, vf } = 0;
    end else begin
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
    end
end endmodule
