
module clock_division(
    i_reset,
    i_clock,
    i_top,
    o_clock
);
    input               i_reset;
    input               i_clock;

    parameter           max_counter = 256;
    parameter           bits = 
        max_counter <= 2          ?  1 :
        max_counter <= 4          ?  2 :
        max_counter <= 8          ?  3 :
        max_counter <= 16         ?  4 :
        max_counter <= 32         ?  5 :
        max_counter <= 64         ?  6 :
        max_counter <= 128        ?  7 :
        max_counter <= 256        ?  8 :
        max_counter <= 512        ?  9 :
        max_counter <= 1024       ? 10 :
        max_counter <= 2048       ? 11 :
        max_counter <= 4096       ? 12 :
        max_counter <= 8192       ? 13 :
        max_counter <= 16384      ? 14 :
        max_counter <= 32768      ? 15 :
        max_counter <= 65536      ? 16 :
        max_counter <= 131072     ? 17 :
        max_counter <= 262144     ? 18 :
        max_counter <= 524288     ? 19 :
        max_counter <= 1048576    ? 20 :
        max_counter <= 2097152    ? 21 :
        max_counter <= 4194304    ? 22 :
        max_counter <= 8388608    ? 23 :
        max_counter <= 16777216   ? 24 :
        max_counter <= 33554432   ? 25 :
        max_counter <= 67108864   ? 26 :
        max_counter <= 134217728  ? 27 :
        max_counter <= 268435456  ? 28 :
        max_counter <= 536870912  ? 29 :
        max_counter <= 1073741824 ? 30 : -1;

    output reg                  o_clock   = 0;

    input      [bits - 1:0]     i_top;
    reg        [bits - 1:0]     t           = 0;
    reg        [bits - 1:0]     counter     = 1;
always @ (posedge i_clock or posedge i_reset) begin
    if (i_reset) begin
        o_clock                   = 0;
        t                           = 0;
        counter                     = 1;
    end else begin
        o_clock                   = t;
        t                           = counter == i_top;
        counter                     = t ? 1 : counter + 1;
    end
end

endmodule