
module uart(
    input                   i_extern_reset,
    input                   i_clock_50mhz,
    input                   i_rx,
    output                  o_tx
);
    wire                    i_reset;
    wire                    i_clock_x8;
    wire [ 7:0]             data_rx;
    reg  [ 7:0]             buf_rx [0:3];
    reg  [ 7:0]             buf_tx              = 0;
    reg  [ 1:0]             idx_rx              = 0;
    reg  [ 1:0]             idx_tx              = 0;
    reg                     i_load_ack          = 0;
    wire                    o_error_parity;
    wire                    o_error_stop_bit;
    wire                    o_store_req;
    wire                    i_clock_rx          = i_clock_50mhz;

    wire                    i_clock_tx;
    wire                    o_load_req;

    uart_rx u_rx(
        .i_reset(i_reset),
        .i_clock_x8(i_clock_rx),
        .i_parity(0),
        .i_data_width(8),
        .i_data(i_rx),
        .o_error_parity(o_error_parity),
        .o_error_stop_bit(o_error_stop_bit),
        .o_store_req(o_store_req),
        .o_data(data_rx)
    );

    reset u_reset(
        .i_extern_reset(i_extern_reset),
        .i_clock_xxmhz(i_clock_50mhz),
        .o_reset(i_reset)
    );

    clock_division #(
        .max_counter(8)
    )div_at_6p25m(
        .i_reset(i_reset),
        .i_clock(i_clock_50mhz),
        .i_top(8),
        .o_clock(i_clock_tx)
    );

    uart_tx u_tx(
        .i_reset(i_reset),
        .i_clock(i_clock_tx),
        .i_parity(0),
        .i_data_width(8),
        .i_data(buf_tx),
        .i_load_ack(i_load_ack),
        .o_load_req(o_load_req),
        .o_data(o_tx)
    );

    wire    need_load           = i_load_ack != o_load_req;

always @ (posedge i_clock_rx) begin
    if (o_store_req) begin
        buf_rx[idx_rx]          = data_rx;
        idx_rx                  = idx_rx + 1;
    end

    if (need_load && idx_tx != idx_rx) begin
        buf_tx                  = buf_rx[idx_tx];
        idx_tx                  = idx_tx + 1;
        i_load_ack              = o_load_req;
    end
end

endmodule
