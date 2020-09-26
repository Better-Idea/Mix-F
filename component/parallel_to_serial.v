
module parallel_to_serial(
    reset,
    clock,
    width,
    data,
    need_load,
    out
);
    parameter                   max_width   = 16;
    parameter                   bits        = 
        max_width <   1 ? -1:
        max_width <=  2 ?  0:
        max_width <=  4 ?  1:
        max_width <=  8 ?  2:
        max_width <= 16 ?  3:
        max_width <= 32 ?  4:
        max_width <= 64 ?  5: -1;

    input                       reset;
    input                       clock;
    input       [bits:0]        width;
    input       [max_width:0]   data;
    output reg                  need_load   = 1;
    output reg                  out         = 0;

    reg                         need_reset  = 0;

    (* KEEP="TRUE"*)
    reg         [bits:0]        i           = 0;

always @ (negedge reset or posedge clock) begin
    if (reset == 0) begin
        need_reset  = 1;
    end else if (need_reset) begin
        need_load   = 1;
        out         = 0;
        need_reset  = 0;
        i           = 0;
    end else begin
        out         = data[i];
        i           = i + 1/*norrow & overflow*/ == width ? 0 : i + 1;
        need_load   = i == 0;
    end
end
endmodule
