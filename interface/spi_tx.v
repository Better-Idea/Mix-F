
// spi_tx u?(
//     .i_reset(i_reset),
//     .i_clock(i_clock),
//     .i_data_width(i_data_width),
//     .i_data(i_data),
//     .i_cpol(i_cpol),
//     .i_cpha(i_cpha),
//     .i_load_ack(i_load_ack),
//     .o_clock(o_clock),
//     .o_bit(o_bit),
//     .o_load_req(o_load_req)
// );

module spi_tx(
    input               i_reset,
    input               i_clock,
    input      [ 3:0]   i_data_width,
    input      [15:0]   i_data,
    input               i_cpol,
    input               i_cpha,
    input               i_load_ack,
    output              o_clock,
    output reg          o_bit           = 0,
    output reg          o_load_req      = 0
);

    reg        [ 3:0]   i               = 0;
    reg                 is_idle         = 1;
    wire                wait_load       = o_load_req != i_load_ack;
    assign              o_clock    = is_idle ? i_cpol : i_clock ^ ~(i_cpol ^ i_cpha);

always @ (posedge i_reset or posedge i_clock) begin
    if (i_reset) begin
        o_bit                           = 0;
        o_load_req                      = 0;
        i                               = i_data_width;
        is_idle                         = 1;
    end else if (wait_load == 0) begin
        i                               = i - 1;
        is_idle                         = 0;
        o_bit                           = i_data[i];

        if (i == 0) begin
            i                           = i_data_width;
            o_load_req                  = ~i_load_ack;
        end
    end else begin
        is_idle                         = 1;
    end
end

endmodule
