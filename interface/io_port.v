
module io_port(
    input       i_enable_output,
    input       i_out,
    output      o_in,
    inout       b_io
);
    assign  o_in = b_io;
    assign  b_io = i_enable_output ? i_out : 1'bz;
endmodule
