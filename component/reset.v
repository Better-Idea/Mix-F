
module reset(
    input       i_extern_reset,
    input       i_clock_xxmhz,
    output reg  o_reset         = 0
);

    reg         once            = 1;
always @ (negedge/*与子时钟错开，确保复位信号不会与子时钟冲突*/ i_clock_xxmhz) begin
    if (once) begin
        if (o_reset ~^ i_extern_reset) begin
            o_reset             = 1;
            once                = 0;
        end
    end else begin
        o_reset                 = 0;

        if (o_reset ^ i_extern_reset) begin
            once                = 1;
        end
    end
end

endmodule
