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
    output reg                  need_store      = 0,
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
    reg                         old_in          = 1;
    reg                         check           = 0; // 奇偶校验

always @ (posedge clock_x8 or negedge reset) begin
    if (reset == 0) begin
        // error_parity            = 0;
        // error_stop_bit          = 0;
        // need_store              = 0;
        // bits                    = 0;
        // i                       = 0;
        step                    = 0;
        state                   = uart_state_receive_start_bit;
        old_in                  = 1;
        latch                   = 1;
        // check                   = 0;
    end else begin
        step                    = step + 1;

        if (step == 4) begin
            latch               = old_in;
        end

        if (step == 0) begin
            old_in              = in; 
            case (state)
            uart_state_receive_start_bit    : begin
                if (latch == 0) begin
                    error_parity    = 0;
                    error_stop_bit  = 0;
                    need_store      = 0;
                    bits            = 0;
                    i               = 0;
                    state           = uart_state_receive_data_bits;
                    check           = 0;
                end
            end
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
            uart_state_receive_stop_bit     : begin
                if (latch == 1) begin
                    need_store      = 1;
                end else begin
                    error_stop_bit  = 1;
                end
                state               = uart_state_receive_start_bit;
            end endcase
        end
    end
end endmodule



