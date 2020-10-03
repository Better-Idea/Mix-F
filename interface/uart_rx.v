`include"uart_define.v"

module uart_rx(
    input                       i_reset,
    input                       i_clock_x8,
    input       [ 1:0]          i_parity,
    input       [ 3:0]          i_data_width,
    input                       i_data,
    output reg                  o_error_parity      = 0,
    output reg                  o_error_stop_bit    = 0,
    output reg                  o_store_req         = 0,
    output reg  [15:0]          o_data              = 0
);
    // 1bit start + 16bit o_data(max) + 1bit i_parity + 1bit stop
    parameter rx_start_bit                      = 0;
    parameter rx_data_bits                      = 1;
    parameter rx_parity_bit                     = 2;
    parameter rx_stop_bit                       = 3;

    reg         [ 3:0]          i               = 0;
    reg         [ 2:0]          step            = 0;
    reg         [ 2:0]          state           = rx_start_bit;
    reg                         latch           = 1;
    reg                         check           = 0; // parity check
always @ (posedge i_reset or posedge i_clock_x8) begin
    if (i_reset) begin
        o_error_parity              = 0;
        o_error_stop_bit            = 0;
        o_store_req                 = 0;
        o_data                      = 0;
        i                           = 0;
        step                        = 0;
        state                       = rx_start_bit;
        latch                       = 1;
        check                       = 0;
    end else if (state == rx_start_bit) begin
        if (latch) begin
            latch                   = i_data;
            step                    = 0;
            state                   = rx_start_bit;
        end else begin
            state                   = step == 7 ? rx_data_bits : rx_start_bit;
            step                    = step + 1;
        end

        o_error_parity              = 0;
        o_error_stop_bit            = 0;
        o_store_req                 = 0;
        i                           = 0;
        check                       = 0;
    end else begin
        step                        = step + 1;

        if (step[2:0] == 4) begin
            latch                   = i_data;

            case (state)
            rx_data_bits: begin
                o_data[i]           = latch;
                check               = check ^ latch;
                i                   = i + 1;

                if (i == i_data_width) begin
                    state           = i_parity[1] ? 
                        rx_parity_bit : 
                        rx_stop_bit;
                end
            end
            rx_parity_bit: begin
                o_error_parity      = check ^ latch ^ i_parity[0];
                state               = rx_stop_bit;
            end
            default: begin
                o_store_req         =  latch;
                o_error_stop_bit    = ~latch;
                state               = rx_start_bit;
            end endcase
        end
    end
end endmodule
