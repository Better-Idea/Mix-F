`timescale 1ns/1ps

`define REG_MSB             31
`define SYS_BITS            32
`define SYS_BITS_SUB6       26
`define SYS_BITS_SUB9       23
`define SYS_BITS_SUB10      22
`define SYS_BITS_SUB12      20
`define CAN_WRITE_DS        (reg_ds != 0)
`define CAN_WRITE_ES        (reg_es != 0)
`define NOT_WRITE_DS        6'b0
`define NOT_WRITE_ES        6'b0

`define ALL_ONE             32'hffff_ffff
`define ALL_ZERO            32'h0000_0000

`define R0                  6'd0
`define RA                  6'd1
`define SP                  6'd2
`define PC                  6'd32

`define DS_IS_PC            (reg_ds[5] == 1)

module vcpu(
    input           rst,
    input           sck,
    input  [15:0]   cmd,
    output [31:0]   opt,
    output [31:0]   sta
);

reg [31:0]  r[0:32];
reg [31:0]  tmp_es;
reg         cf;
reg         zf;
reg         nf;
reg         vf;
reg [31:0]  n;
reg [31:0]  m;

assign opt = r[cmd[4:0]];

reg [ 5:0]  reg_ds;
reg [ 5:0]  reg_es;

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
// nand  ~(A & B) -> ~A | ~B    0   0
// xor     A ^ B                0   1
// or      A | B                1   0
// and     A & B                1   1
// 参数
reg         bitwise_m0  = 0;
reg         bitwise_m1  = 0;
reg         bitwise_req = 0;

// 输出
reg         bitwise_ack = 0;
reg [31:0]  tmp_ds_bitwise;

always @(posedge (bitwise_req != bitwise_ack)) begin
    { tmp_ds_bitwise } =
        ((bitwise_m1 ? n : ~n      ) & (bitwise_m0 ? m : `ALL_ONE)) | 
        ((bitwise_m0 ? n : `ALL_ONE) & (bitwise_m1 ? m : ~m      ));
    { bitwise_ack } = bitwise_req;
end

// 赋值操作
// 参数
reg         move_req = 0;

// 输出
reg         move_ack = 0;
reg [31:0]  tmp_es_move;
reg [31:0]  tmp_ds_move;

always @(posedge (move_req != move_ack)) begin
    tmp_ds_move = n;
    tmp_es_move = m;
end

// 移位操作
// 参数
`define SHIFT_RIGHT         1'b0
`define SHIFT_LEFT          1'b1

reg [ 5:0]  shift_bits      = 0;
reg         shift_mode      = 0;
reg         shift_with_sign = 0;
reg         shift_req       = 0;

// 输出
reg         shift_ack       = 0;
reg [31:0]  tmp_ds_shift;

always @(posedge (shift_req != shift_ack)) begin
    if (shift_mode == `SHIFT_LEFT) begin
        { tmp_ds_shift } = { n } << shift_bits;
    end else begin
        { tmp_ds_shift } = { { `SYS_BITS{ shift_with_sign & n[`REG_MSB] } }, n } >> shift_bits;
    end
end

// 访存操作
// 参数
`define MEM_MODE_READ       0
`define MEM_MODE_WRITE      1

reg         mem_mode = 0;
reg         mem_req = 0;

// 输出
reg         mem_ack = 0;
reg [31:0]  tmp_ds_mem;

always @(posedge (move_req != move_ack)) begin
    { tmp_ds_mem } = n + m;

    // 
end

reg [31:0]  tmp_ds_mul;
reg [31:0]  tmp_ds_bl;

`define I_ADD               0
`define I_BITWISE           1
`define I_MOVE              2
`define I_SHIFT             3
`define I_MEM               4

`define I_MAX               15 /*当 I_MAX 需要变大时需要修改下方 d 的元素个数*/

// i_serial 最大值不能超过 d 数组的索引
reg [ 3:0]  i_serial = 0;

wire[31:0]  d[0:`I_MAX];    // 目的寄存器
wire[31:0]  e[0:`I_MAX];    // 目的寄存器

assign d     [`I_ADD    ] = tmp_ds_add;
assign d     [`I_BITWISE] = tmp_ds_bitwise;
assign d     [`I_MOVE   ] = tmp_ds_move;
assign d     [`I_SHIFT  ] = tmp_ds_shift;
assign d     [`I_MEM    ] = tmp_ds_mem;

assign e     [`I_MOVE   ] = tmp_es_move;

always @(posedge sck) begin
    { reg_es } = 0;
    { reg_ds } = 0;

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

        // lw
        3'b?10: begin
            `define IS_WRITE    {cmd[15]}
            `define RS1         {1'b1, cmd[9:7]}
            `define RD          {1'b1, cmd[4:2]}
            `define UMM7        {cmd[5], cmd[12:10], cmd[6], 2'b0 }

            { i_serial } = `I_MEM;
            { reg_ds } = `RD;
            { n } = r[`RS1];
            { m } = `UMM7;

            { mem_mode } = `IS_WRITE;
            { mem_req } = !mem_ack;
        end

        default: begin
            
        end
        endcase
    end

    2'b01: begin
        casez({cmd[15:10], cmd[6:5]})
        // addi
        // addiw
        8'b000???_??, 8'b001???_??: begin
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
        8'b011???_??: begin
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

        // and
        8'b100011_11: begin
            `define RD          {1'b1, cmd[9:7]}
            `define RS2         {1'b1, cmd[4:2]}

            { i_serial } = `I_BITWISE;
            { reg_ds } = `RD;
            { n } = r[`RD];
            { m } = r[`RS2];

            { bitwise_m0 } = 0;
            { bitwise_m1 } = 0;
            { bitwise_req } = !bitwise_ack;
        end

        // addw
        // sub
        // subw
        8'b100111_0?, 8'b100011_00: begin
            `define RD          {1'b1, cmd[9:7]}
            `define RS2         {1'b1, cmd[4:2]}
            `define IS_SUB      {cmd[8]}

            { i_serial } = `I_ADD;
            { reg_ds } = `RD;
            { n } = r[`RD];
            { m } = r[`RS2];

            { add_neg_m } = `IS_SUB;
            { add_with_cf } = `IS_SUB;
            { add_req } = !add_ack;
        end

        // andi
        8'b100?10_??: begin
            `define RD          {1'b1, cmd[9:7]}
            `define IMM6        {cmd[12], cmd[6:2]}

            { i_serial } = `I_BITWISE;
            { reg_ds } = `RD;
            { n } = r[`RD];
            { m } = { {`SYS_BITS_SUB6{ cmd[12] }}, `IMM6 } ;

            { bitwise_m0 } = 0;
            { bitwise_m1 } = 0;
            { bitwise_req } = !bitwise_ack;
        end

        // beqz cmd[13] = 0
        // bnqz cmd[13] = 1
        8'b11????_??: begin
            `define NEG         {cmd[13]}
            `define RS1         {1'b1, cmd[9:7]}
            `define IMM9        {cmd[12], cmd[6:5], cmd[2], cmd[11:10], cmd[4:3], 1'b0}

            if ((r[`RS1] == 0) ^ `NEG) begin
                { i_serial } = `I_ADD;
                { reg_ds } = `PC;
                { n } = r[`PC];
                { m } = { {`SYS_BITS_SUB9{ cmd[12] }}, `IMM9 } ;

                { add_neg_m } = 0;
                { add_with_cf } = 0;
                { add_req } = !add_ack;

                // TODO:需要确认是否需要忽略一次 PC + 2 =========================
            end
        end

        // j    cmd[15] = 0
        // jal  cmd[15] = 1
        8'b?01???_??: begin
            `define JAL         {cmd[15]}
            `define IMM12       {cmd[12], cmd[8], cmd[10:9], cmd[6], cmd[7], cmd[2], cmd[11], cmd[5:3], 1'b0}

            if (`JAL) begin
                { reg_es } = `RA;
                { tmp_es } = r[`PC] + 2;
            end

            { i_serial } = `I_ADD;
            { reg_ds } = `PC;
            { n } = r[`PC];
            { m } = { {`SYS_BITS_SUB12{ cmd[12] }}, `IMM12 };

            { add_neg_m } = 0;
            { add_with_cf } = 0;
            { add_req } = !add_ack;

            // TODO:需要确认是否需要忽略一次 PC + 2 =========================
        end

        // li   
        // lui  
        8'b01????_??: begin
            `define IS_UPPER    {cmd[13]}
            `define IMM6        {cmd[12], cmd[6:2]}
            `define RD          {cmd[11:7]}

            // error
            if (`IS_UPPER && (`RD == `SP || `IMM6 == 0)) begin
                
            end else begin
                { i_serial } = `I_MOVE;
                { reg_ds } = `RD;
                // { reg_es } = `NOT_WRITE_ES;
                { n } = `IS_UPPER ? 
                    { {`SYS_BITS_SUB12{ cmd[12] }}, `IMM6 << 12 } : 
                    { {`SYS_BITS_SUB6{ cmd[12] }}, `IMM6 };
                // { m } = 0;

                { move_req } = !move_ack;
            end
        end

        // or   8'b100011_10
        // and  8'b100011_11
        // xor  8'b100011_01
        8'b100011_??: begin
            `define RD          {1'b1, cmd[9:7]}
            `define RS2         {1'b1, cmd[4:2]}

            { i_serial } = `I_BITWISE;
            { reg_ds } = `RD;
            { n } = r[`RD];
            { m } = r[`RS2];

            { bitwise_m1, bitwise_m0 } = cmd[9:8];
            { bitwise_req } = !bitwise_ack;

            // TODO: nand 指令并不存在
        end

        // srai
        // srli
        8'b100?0?_??: begin
            `define WITH_SIGN       {cmd[10]}
            `define RD              {1'b1, cmd[9:7]}
            `define UMM6            {cmd[12], cmd[6:2]}

            { i_serial } = `I_SHIFT;
            { reg_ds } = `RD;
            { n } = r[`RD];
            // { m } = `UMM6;

            { shift_bits } = `UMM6;
            { shift_mode } = `SHIFT_RIGHT;
            { shift_with_sign } = `WITH_SIGN;
            { shift_req } = !shift_ack;
        end

        default: // ebreak
            if (cmd[15:0] == 16'b1001_0000_0000_0010) begin
                
            end
        endcase
    end
    
    2'b10: begin
        casez (cmd[15:12])
        // add
        4'b1001: begin
            `define RD          (cmd[11:7])
            `define RS2         (cmd[6:2])

            if (`RD != `R0 && `RS2 != `R0) begin
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

        // jalr
        4'b1001: begin
            `define RS1         (cmd[11:7])
            `define CHECK       (cmd[6:2] == 0)
            
            if (`CHECK) begin
                { i_serial } = `I_MOVE;
                { reg_ds } = `PC;
                { reg_es } = `RA;
                { n } = r[`RS1];
                { m } = r[`PC] + 2;

                { move_req } = !move_ack;
            end else begin
                
            end
        end

        // jr
        4'b1000: begin
            `define RS1         (cmd[11:7])
            `define CHECK       (cmd[6:2] == 0 && `RS1 != 0)

            if (`CHECK) begin
                { i_serial } = `I_MOVE;
                { reg_ds } = `PC;
                // { reg_es } = `NOT_WRITE_DS;
                { n } = r[`RS1];
                // { m } = 0;

                { move_req } = !move_ack;
            end else begin
                
            end
        end

        // lwsp
        // swsp
        4'b?10?: begin
            `define IS_WRITE    {cmd[15]}
            `define RD          {cmd[11:7]}
            `define UMM8        {cmd[3:2], cmd[12], cmd[6:4], 2'b0}
            `define CHECK       `RD != 0

            if (`CHECK) begin
                { i_serial } = `I_MEM;
                { reg_ds } = `RD;
                { n } = r[`RS1];
                { m } = `UMM8;

                { mem_mode } = `IS_WRITE;
                { mem_req } = !mem_ack;
            end else begin
                
            end
        end

        // mv
        4'b1000: begin
            `define RD          {cmd[11:7]}
            `define RS2         {cmd[6:2]}
            `define CHECK       `RS2 != 0

            if (`CHECK) begin
                { i_serial } = `I_MOVE;
                { reg_ds } = `RD;
                { n } = r[`RS2];

                { move_req } = !move_ack;
            end else begin
                
            end
        end

        // slli
        4'b000?: begin
            `define UMM6    {cmd[12], cmd[4:0]}
            `define RD      {cmd[11:7]}

            { i_serial } = `I_SHIFT;
            { reg_ds } = `RD;
            { n } = r[`RD];
            // { m } = `UMM6;

            { shift_bits } = `UMM6;
            { shift_mode } = `SHIFT_LEFT;
            { shift_with_sign } = 0;
            { shift_req } = !shift_ack;
        end

        default: begin
            
        end
        endcase
    end
    
    // 2'b11
    default:
        casez({cmd[31:25], cmd[14:12], cmd[6:2]})
        // add
        // addw
        15'b0000000_000_011?0: begin
            `define RD      {cmd[11:7]}
            `define RS1     {cmd[19:15]}
            `define RS2     {cmd[24:20]}

            { i_serial } = `I_ADD;
            { reg_ds } = `RD;
            { n } = r[`RS1];
            { m } = r[`RS2];

            { add_neg_m } = 0;
            { add_with_cf } = 0;
            { add_req } = !add_ack;
        end

        // addi
        // addiw
        15'b???????_000_001?0: begin
            `define RD      {cmd[11:7]}
            `define RS1     {cmd[19:15]}
            `define IMM12   {cmd[31:20]}

            { i_serial } = `I_ADD;
            { reg_ds } = `RD;
            { n } = r[`RS1];
            { m } = { { `SYS_BITS_SUB12{ cmd[31] } }, `IMM12 };

            { add_neg_m } = 0;
            { add_with_cf } = 0;
            { add_req } = !add_ack;
        end

        // or   15'b0000000_111_01000
        // and  15'b0000000_111_01100
        // xor  15'b0000000_111_00100
        15'b0000000_111_0??00: begin
            `define RD      {cmd[11: 7]}
            `define RS1     {cmd[19:15]}
            `define RS2     {cmd[24:20]}

            { i_serial } = `I_BITWISE;
            { reg_ds } = `RD;
            { n } = r[`RS1];
            { m } = r[`RS2];

            { bitwise_m1, bitwise_m0 } = cmd[5:4];
            { bitwise_req } = !bitwise_ack;

            // TODO: nand 指令并不存在
        end

        // or   15'b0000000_110_01100
        // and  15'b0000000_111_01100
        // xor  15'b0000000_100_01100
        15'b0000000_1??_01100: begin
            `define RD      {cmd[11: 7]}
            `define RS1     {cmd[19:15]}
            `define RS2     {cmd[24:20]}

            { i_serial } = `I_BITWISE;
            { reg_ds } = `RD;
            { n } = r[`RS1];
            { m } = r[`RS2];

            // 16bit/32bit xor 指令 opc 不一致，bad design
            { bitwise_m1, bitwise_m0 } = cmd[13:12] == 0 ? 2'b01 : cmd[13:12];
            { bitwise_req } = !bitwise_ack;

            // TODO: nand 指令并不存在
        end

        default: begin
            
        end
        endcase
    endcase
end

`define REG_DS              r[reg_ds[3:0]]
`define REG_ES              r[reg_es[3:0]]
`define CUR_TMP_DS          d[i_serial]
`define CUR_TMP_ES          e[i_serial]

always @(negedge sck) begin
    begin
        if (`CAN_WRITE_DS) begin
            `REG_DS = `CUR_TMP_DS;
        end

        if (`CAN_WRITE_ES) begin
            `REG_ES = `CUR_TMP_ES;
        end
    end
end endmodule
