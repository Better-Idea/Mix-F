`timescale 1ns / 1ps
`include"define.v"

module uart_rx(
    input                       reset,
    input                       clock_x8,
    input       [ 1:0]          parity,
    input       [ 3:0]          width,
    input                       in,
    output reg                  error_parity    = 0,
    output reg                  error_stop_bit  = 0,
    output reg                  req_store       = 0,
    output reg  [15:0]          bits            = 0
);
    // 1bit start + 16bit data(max) + 1bit parity + 1bit stop
    parameter uart_state_receive_start_bit      = 0;
    parameter uart_state_receive_data_bits      = 1;
    parameter uart_state_receive_parity_bit     = 2;
    parameter uart_state_receive_stop_bit       = 3;

    reg         [ 3:0]          i               = 0;
    reg         [ 2:0]          step            = 0;
    reg         [ 2:0]          state           = uart_state_receive_start_bit;
    reg                         latch           = 1;
    reg                         check           = 0; // 奇偶校验

always @ (posedge clock_x8 or negedge reset) begin
    if (reset == 0) begin
        error_parity                = 0;
        error_stop_bit              = 0;
        req_store                   = 0;
        bits                        = 0;
        i                           = 0;
        step                        = 0;
        state                       = uart_state_receive_start_bit;
        latch                       = 1;
        check                       = 0;
    end else if (state == uart_state_receive_start_bit) begin
        if (latch) begin
            latch                   = in;
            step                    = 0;
        end else begin
            state                   = step == 7 ? uart_state_receive_data_bits : uart_state_receive_start_bit;
            step                    = step + 1;
        end

        if (state == uart_state_receive_data_bits) begin
            error_parity            = 0;
            error_stop_bit          = 0;
            req_store               = 0;
            i                       = 0;
            check                   = 0;
        end
    end else begin
        if (step == 3) begin
            latch                   = in;

            case (state)
            uart_state_receive_data_bits    : begin
                bits[i]             = latch;
                check               = check ^ latch;
                i                   = i + 1;

                if (i == width) begin
                    state           = parity[1] ? 
                        uart_state_receive_parity_bit : 
                        uart_state_receive_stop_bit;
                end
            end
            uart_state_receive_parity_bit   : begin
                error_parity        = check ^ latch ^ parity[0];
                state               = uart_state_receive_stop_bit;
            end
            default                         : begin
                req_store           = latch;
                error_stop_bit      = ! latch;
                state               = uart_state_receive_start_bit;
            end endcase
        end

        step                        = step + 1;
    end
end endmodule
