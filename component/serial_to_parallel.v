

module serial_to_parallel(
    reset,
    clock,
    width,
    in,
    need_store,
    data
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
    input                       in;
    output reg                  need_store  = 0;
    output reg  [max_width:0]   data        = 0;

    reg                         need_reset  = 0;

    (* KEEP="TRUE"*)
    reg         [bits:0]        i           = 0;

always @ (negedge reset or posedge clock) begin
    if (reset == 0) begin
        need_reset  = 1;
    end else if (need_reset) begin
        need_store  = 0;
        data        = 0;
        need_reset  = 0;
        i           = 0;
    end else begin
        data[i]     = in;
        i           = i + 1 == width ? 0 : i + 1;
        need_store  = i == 0;
    end
end
endmodule
