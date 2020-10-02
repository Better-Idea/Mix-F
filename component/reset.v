
module reset(
    input       i_extern_reset,
    input       i_clock_xxmhz,
    output reg  o_reset         = 0
);

always @ (negedge/*与子时钟错开，确保复位信号不会与子时钟冲突*/ i_clock_xxmhz) begin
    if (o_reset ~^ i_clock_xxmhz) begin
        o_reset                 = ~o_reset;
    end
end

endmodule
