`include"uart_define.v"

module uart_tx(
    input                       i_reset,
    input                       i_clock,
    input       [ 1:0]          i_parity,
    input       [ 3:0]          i_data_width,
    input       [15:0]          i_data,
    input                       i_load_ack,
    output reg                  o_load_req  = 1,
    output reg                  o_data      = 1 // NOTE:specified IDLE state
);
    // 1bit start + 16bit data(max) + 1bit i_parity + 1bit stop
    parameter tx_start_bit                  = 0;
    parameter tx_data_bits                  = 1;
    parameter tx_parity_bit                 = 2;
    parameter tx_stop_bit                   = 3;

    reg                         parity      = 0;
    reg         [ 4:0]          i           = 0;
    reg         [ 1:0]          state       = tx_start_bit;
    wire                        is_idle     = i_load_ack != o_load_req;
always @ (posedge i_clock) begin
    if (i_reset) begin
        o_load_req              = 1;
        o_data                  = 1;
        parity                  = 0;
        i                       = 0;
        state                   = tx_start_bit;
    end else if (is_idle == 0) casex(state)
    tx_start_bit: begin
        parity                  = 0;
        i                       = 0;
        o_data                  = 0;
        state                   = tx_data_bits;
    end
    tx_data_bits: begin
        o_data                  = i_data[i];
        parity                  = i_data[i] ^ parity;
        i                       = i + 1;

        if (i == i_data_width) begin
            i                   = 0;
            state               = i_parity[1] ? 
                tx_parity_bit : 
                tx_stop_bit;
        end
    end
    tx_parity_bit: begin
        o_data                  = parity ^ i_parity[0];
        state                   = tx_stop_bit;
    end
    default: begin
        o_load_req              = ~i_load_ack;
        o_data                  = 1;
        state                   = tx_start_bit;
    end
    endcase
end
endmodule
