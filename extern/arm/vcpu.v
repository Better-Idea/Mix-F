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
    reg [31:0] t;
    reg in_it_block = 0;
    reg cf = 0;
    reg zf = 0;
    reg nf = 0;
    reg of = 0;
    
    reg tmp_cf = 0;
    reg tmp_zf = 0;
    reg tmp_nf = 0;
    reg tmp_of = 0;
always @(posedge sck) begin
    casez(cmd[15:8])
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

        8'b0001_????: begin
            `define IS_IMM_RM   cmd[10]

            // cmd[9]
            // - 0:add
            // - 1:sub
            `define IS_SUB      cmd[9]

            `define RM          cmd[8:6]
            `define RN          cmd[5:3]
            `define RD          cmd[2:0]

            { t } = `IS_IMM_RM ? `RM : r[`RM];
            { t } = `IS_SUB ? -t : t;
            { tmp_of } = r[`RN][`INT_MSB] == t[`INT_MSB];
            { tmp_cf, r[`RD] } = r[`RN] + t;

            if (`RD != `PC && !in_it_block) begin
                nf = r[`RD][`INT_MSB];
                zf = r[`RD] == 0;
                cf = tmp_cf;

                // 操作前相同符号位，相加后符号位不同了就表示溢出了
                of = tmp_of ? tmp_of != r[`RD][`INT_MSB] : 0;
            end

            `undef IS_IMM_RM
            `undef IS_SUB
            `undef RM
            `undef RN
            `undef RD
        end

        default: begin
            
        end
    endcase
end endmodule