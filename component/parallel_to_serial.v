`timescale 1ns / 1ps

module parallel_to_serial(
    input                       reset,
    input                       clock,
    input       [ 4:0]          width,
    input       [31:0]          bits,
    output reg                  need_load = 0,
    output reg                  out       = 0
);
    reg [4:0] i = 0;

always @ (posedge clock or negedge reset) begin
    if (reset == 0) begin
        i           = 0;
        need_load   = 0;
        out         = 0;
    end else begin
        out         = bits[i];
        i           = i + 1;
        need_load   = i == width;
        i           = need_load ? 0 : i;
    end
end
endmodule
