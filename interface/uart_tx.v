`timescale 1ns / 1ps

`include"define.v"

module uart_tx(
    input                       reset,
    input                       clock,
    input       [ 1:0]          parity,
    input       [ 3:0]          width,
    input       [15:0]          bits,
    output reg                  need_load   = 0,
    output reg                  out         = 1
);
    // 1bit start + 16bit data(max) + 1bit parity + 1bit stop
    parameter uart_state_send_start_bit     = 0;
    parameter uart_state_send_data_bits     = 1;
    parameter uart_state_send_parity_bit    = 2;
    parameter uart_state_send_stop_bit      = 3;

    reg                         p           = 0;
    reg         [ 4:0]          i           = 0;
    reg         [ 1:0]          state       = uart_state_send_start_bit;
always @ (posedge clock or negedge reset) begin
    if (reset == 0) begin
        need_load               = 0;
        out                     = 1;
        p                       = 0;
        i                       = 0;
        state                   = uart_state_send_start_bit;
    end else case (state)
        uart_state_send_start_bit : begin
            need_load           = 0;
            p                   = 0;
            i                   = 0;
            out                 = 0;
            state               = uart_state_send_data_bits;
        end
        uart_state_send_data_bits : begin
            out                 = bits[i];
            p                   = bits[i] ^ p;
            i                   = i + 1;

            if (i == width) begin
                i               = 0;
                state           = parity[1] ? 
                    uart_state_send_parity_bit : 
                    uart_state_send_stop_bit;
            end
        end
        uart_state_send_parity_bit: begin
            out                 = p ^ parity[0];
            state               = uart_state_send_stop_bit;
        end
        uart_state_send_stop_bit  : begin
            need_load           = 1;
            out                 = 1;
            state               = uart_state_send_start_bit;
        end
    endcase
end
endmodule
