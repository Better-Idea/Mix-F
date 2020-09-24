`timescale 1ns / 1ps

module uart(
    input                   reset,
    input                   clock_50mhz,
    input                   rx,
    output                  tx
);

    reg  [ 7:0] counter_1mhz            = 0;
    reg  [ 2:0] counter_125khz          = 0;

    reg         clock_1mhz              = 0;
    reg         clock_125khz            = 0;
    reg         ack_load                = 0;
    wire        req_load;
    reg  [15:0] obits                   = 0;
    reg  [ 7:0] obuf [0:3];
    reg  [ 1:0] i_rx                    = 0;
    reg  [ 1:0] i_tx                    = 0;

    wire        error_parity;
    wire        error_stop_bit;
    wire        req_store;
    wire [15:0] bits;

    uart_tx u0(
        .reset(reset),
        .clock(clock_125khz),
        .parity(0),
        .width(8),
        .bits(obits),
        .ack_load(ack_load),
        .req_load(req_load),
        .out(tx)
    );

    uart_rx u1(
        .reset(reset),
        .clock_x8(clock_1mhz),
        .parity(0),
        .width(8),
        .in(rx),
        .error_parity(error_parity),
        .error_stop_bit(error_stop_bit),
        .req_store(req_store),
        .bits(bits)
    );

always @ (negedge reset or posedge clock_50mhz) begin
    if (reset == 0) begin
        counter_1mhz                        = 0;
        clock_1mhz                          = 0;
    end else begin
        // 50mhz / 50 -> 1mhz
        clock_1mhz                          = counter_1mhz == 49;
        counter_1mhz                        = clock_1mhz ? 0 : counter_1mhz + 1; 
    end
end

always @ (negedge reset or posedge clock_1mhz) begin
    if (reset == 0) begin
        counter_125khz                      = 0;
        clock_125khz                        = 0;
    end else begin
        // 1mhz / 8 -> 125khz
        clock_125khz                        = counter_125khz == 7;
        counter_125khz                      = clock_125khz ? 0 : counter_125khz + 1;
    end
end

always @ (posedge req_store) begin
    obuf[i_rx]                              = bits;
    i_rx                                    = i_rx + 1;
end

always @ (negedge reset or negedge clock_125khz) begin
    if (reset == 0) begin
        ack_load                            = 0;
    end else if (i_tx == i_rx) begin
        ack_load                            = 0;
    end else if (req_load) begin
        obits                               = obuf[i_tx];
        i_tx                                = i_tx + 1;
        ack_load                            = 1;
    end
end

endmodule
