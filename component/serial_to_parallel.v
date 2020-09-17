`timescale 1ns / 1ps

module serial_to_parallel(
    input                       reset,
    input                       clock,
    input       [ 4:0]          width,
    input                       in,
    output reg  [31:0]          bits        = 0,
    output reg                  need_store  = 0
);
    reg [4:0] i = 0;

always @ (posedge clock or negedge reset) begin
    if (reset == 0) begin
        i           = 0;
        bits        = 0;
        need_store  = 0;
    end else begin
        bits[i]     = in;
        i           = i + 1;
        need_store  = i == width;
        i           = need_store ? 0 : i;
    end
end
endmodule
