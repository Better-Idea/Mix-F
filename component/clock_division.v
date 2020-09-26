
module clock_division(
    input               reset,
    input               clock,
    output reg          new_clock   = 0
);

    parameter           div = 2;
    parameter           max_counter = div - 1;
    parameter           bits = 
        max_counter <   1 ? -1:
        max_counter <   2 ? 1 :
        max_counter <   4 ? 2 :
        max_counter <   8 ? 3 :
        max_counter <  16 ? 4 :
        max_counter <  32 ? 5 :
        max_counter <  64 ? 6 :
        max_counter < 128 ? 7 :
        max_counter < 256 ? 8 :
        max_counter < 512 ? 9 : -1;

    reg                 need_reset  = 0;
    reg                 t           = 0;
    reg [bits - 1:0]    counter     = 1;
always @ (negedge reset or posedge clock) begin
    if (reset == 0) begin
        need_reset                  = 1;
    end else if (need_reset) begin
        new_clock                   = 0;
        need_reset                  = 0;
        t                           = 0;
        counter                     = 1;
    end else begin
        new_clock                   = t;
        t                           = counter == max_counter;
        counter                     = t ? 0 : counter + 1;
    end
end

endmodule