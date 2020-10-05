
module main(
    input           reset,
    input           clock_50mhz,
    output reg      lcd_cs              = 1,
    output reg      lcd_reset           = 1,
    output reg      lcd_a0              = 0,
    output          lcd_sda,
    output          lcd_sck,
    output reg      lcd_led             = 1
);

    reg             global_reset        = 0;
    reg  [7:0]      delay_ms            = 0;
    wire            clock_5mhz;
    wire            clock_1khz;
    wire            clock_spi           = clock_5mhz;

    clock_division #(
        .max_counter(10)
    ) div0(
        .reset(global_reset),
        .clock(clock_50mhz),
        .top(10),
        .new_clock(clock_5mhz)
    );

    clock_division #(
        .max_counter(5000)
    ) div1(
        .reset(global_reset),
        .clock(clock_5mhz),
        .top(5000),
        .new_clock(clock_1khz)
    );

    reg             delay_stop          = 0;
    reg             delay_start         = 0;
    wire            delay_finished;
    wire            under_delay         = delay_start != delay_stop;

    clock_division #(
        .max_counter(200)
    ) div2(
        .reset(global_reset),
        .clock(clock_1khz & under_delay),
        // .clock(clock_50mhz & under_delay),
        .top(delay_ms),
        .new_clock(delay_finished)
    );

    reg             tx_start            = 0;
    reg             tx_stop             = 0;
    reg  [7:0]      data_tx             = 0;
    wire            need_load;
    wire            under_tx            = tx_start != tx_stop;

    assign          lcd_sck             = clock_spi & under_tx;

    parameter       bit_cmd             = 1'b0;
    parameter       bit_dat             = 1'b1;

    parallel_to_serial #(
        .max_width(8)
    ) spi_tx (
        .reset(global_reset),
        .clock(lcd_sck),
        .width(8),
        .data(data_tx),
        .need_load(need_load),
        .out(lcd_sda)
    );

    parameter       step_ini0           = 0;
    parameter       step_ini1           = 1;
    parameter       step_ini2           = 2;
    parameter       step_ini3           = 3;
    parameter       step_ini4           = 4;

    reg  [3:0]      step                = step_ini0;
    reg  [7:0]      i                   = 0;
    reg             wait_tx             = 0;
    wire            clock_main          = clock_50mhz;

always @ (posedge delay_finished or posedge global_reset) begin
    delay_stop                          = global_reset ? 0 : ~delay_stop;
end

always @ (posedge need_load or posedge global_reset) begin
    tx_stop                             = global_reset ? 0 : ~tx_stop;
end

always @ (negedge clock_main) begin
    if (reset == 0 && global_reset == 0) begin
        global_reset                    = 1;
    end else if (reset == 1 && global_reset == 1) begin
        global_reset                    = 0;
    end

    if (global_reset) begin
        lcd_cs                          = 1;
        lcd_reset                       = 0;
        lcd_a0                          = 0;
        lcd_led                         = 1;
        delay_ms                        = 0;
        delay_start                     = 0;
        step                            = step_ini0;
    end else if (~under_delay & ~(wait_tx & under_tx)) casex(step)
    step_ini0: begin
        lcd_reset                       = 0;
        delay_ms                        = 5;
        delay_start                     = ~delay_start;
        step                            = step_ini1;
    end
    step_ini1: begin
        lcd_reset                       = 1;
        lcd_cs                          = 1;
        delay_ms                        = 5;
        delay_start                     = ~delay_start;
        step                            = step_ini2;
    end
    step_ini2: begin
        lcd_cs                          = 0;
        step                            = step_ini3;
    end
    step_ini3: begin
        if (i == 0) begin
            {delay_ms, delay_start} = {8'd200, ~delay_start};
            // {delay_ms, delay_start}     = {8'd20, ~delay_start};
        end

        casex(i)
        0 : { lcd_a0, data_tx }         = { bit_cmd, 8'h11 };

        //------------------------------------ST7735S Frame Rate-----------------------------------------//
        1 : { lcd_a0, data_tx }         = { bit_cmd, 8'hB1 };
        2 : { lcd_a0, data_tx }         = { bit_dat, 8'h05 };
        3 : { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        4 : { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        5 : { lcd_a0, data_tx }         = { bit_cmd, 8'hB2 };
        6 : { lcd_a0, data_tx }         = { bit_dat, 8'h05 };
        7 : { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        8 : { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        9 : { lcd_a0, data_tx }         = { bit_cmd, 8'hB3 };
        10: { lcd_a0, data_tx }         = { bit_dat, 8'h05 };
        11: { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        12: { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        13: { lcd_a0, data_tx }         = { bit_dat, 8'h05 };
        14: { lcd_a0, data_tx }         = { bit_dat, 8'h3C };
        15: { lcd_a0, data_tx }         = { bit_dat, 8'h3C };

        //------------------------------------End ST7735S Frame Rate-----------------------------------------//
        16: { lcd_a0, data_tx }         = { bit_cmd, 8'hB4 }; //Dot inversion
        17: { lcd_a0, data_tx }         = { bit_dat, 8'h03 };
        18: { lcd_a0, data_tx }         = { bit_cmd, 8'hC0 };
        19: { lcd_a0, data_tx }         = { bit_dat, 8'h28 };
        20: { lcd_a0, data_tx }         = { bit_dat, 8'h08 };
        21: { lcd_a0, data_tx }         = { bit_dat, 8'h04 };
        22: { lcd_a0, data_tx }         = { bit_cmd, 8'hC1 };
        23: { lcd_a0, data_tx }         = { bit_dat, 8'hC0 };
        24: { lcd_a0, data_tx }         = { bit_cmd, 8'hC2 };
        25: { lcd_a0, data_tx }         = { bit_dat, 8'h0D };
        26: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        27: { lcd_a0, data_tx }         = { bit_cmd, 8'hC3 };
        28: { lcd_a0, data_tx }         = { bit_dat, 8'h8D };
        29: { lcd_a0, data_tx }         = { bit_dat, 8'h2A };
        30: { lcd_a0, data_tx }         = { bit_cmd, 8'hC4 };
        31: { lcd_a0, data_tx }         = { bit_dat, 8'h8D };
        32: { lcd_a0, data_tx }         = { bit_dat, 8'hEE };

        //---------------------------------End ST7735S Power Sequence-------------------------------------//
        32: { lcd_a0, data_tx }         = { bit_cmd, 8'hC5 }; //VCOM
        33: { lcd_a0, data_tx }         = { bit_dat, 8'h1A };
        34: { lcd_a0, data_tx }         = { bit_cmd, 8'h36 }; //MX, MY, RGB mode
        35: { lcd_a0, data_tx }         = { bit_dat, 8'hC0 };

        //------------------------------------ST7735S Gamma Sequence-----------------------------------------//
        36: { lcd_a0, data_tx }         = { bit_cmd, 8'hE0 };
        37: { lcd_a0, data_tx }         = { bit_dat, 8'h04 };
        38: { lcd_a0, data_tx }         = { bit_dat, 8'h22 };
        39: { lcd_a0, data_tx }         = { bit_dat, 8'h07 };
        40: { lcd_a0, data_tx }         = { bit_dat, 8'h0A };
        41: { lcd_a0, data_tx }         = { bit_dat, 8'h2E };
        42: { lcd_a0, data_tx }         = { bit_dat, 8'h30 };
        43: { lcd_a0, data_tx }         = { bit_dat, 8'h25 };
        44: { lcd_a0, data_tx }         = { bit_dat, 8'h2A };
        45: { lcd_a0, data_tx }         = { bit_dat, 8'h28 };
        46: { lcd_a0, data_tx }         = { bit_dat, 8'h26 };
        47: { lcd_a0, data_tx }         = { bit_dat, 8'h2E };
        48: { lcd_a0, data_tx }         = { bit_dat, 8'h3A };
        49: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        50: { lcd_a0, data_tx }         = { bit_dat, 8'h01 };
        51: { lcd_a0, data_tx }         = { bit_dat, 8'h03 };
        52: { lcd_a0, data_tx }         = { bit_dat, 8'h13 };
        53: { lcd_a0, data_tx }         = { bit_cmd, 8'hE1 };
        54: { lcd_a0, data_tx }         = { bit_dat, 8'h04 };
        55: { lcd_a0, data_tx }         = { bit_dat, 8'h16 };
        56: { lcd_a0, data_tx }         = { bit_dat, 8'h06 };
        57: { lcd_a0, data_tx }         = { bit_dat, 8'h0D };
        58: { lcd_a0, data_tx }         = { bit_dat, 8'h2D };
        59: { lcd_a0, data_tx }         = { bit_dat, 8'h26 };
        60: { lcd_a0, data_tx }         = { bit_dat, 8'h23 };
        61: { lcd_a0, data_tx }         = { bit_dat, 8'h27 };
        62: { lcd_a0, data_tx }         = { bit_dat, 8'h27 };
        63: { lcd_a0, data_tx }         = { bit_dat, 8'h25 };
        64: { lcd_a0, data_tx }         = { bit_dat, 8'h2D };
        65: { lcd_a0, data_tx }         = { bit_dat, 8'h3B };
        66: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        67: { lcd_a0, data_tx }         = { bit_dat, 8'h01 };
        68: { lcd_a0, data_tx }         = { bit_dat, 8'h04 };
        69: { lcd_a0, data_tx }         = { bit_dat, 8'h13 };

        //------------------------------------End ST7735S Gamma Sequence-----------------------------------------//
        70: { lcd_a0, data_tx }         = { bit_cmd, 8'h3A }; //65k mode
        71: { lcd_a0, data_tx }         = { bit_dat, 8'h05 };
        72: { lcd_a0, data_tx }         = { bit_cmd, 8'h29 }; //Display on

        73: { lcd_a0, data_tx }         = { bit_cmd, 8'h2A };
        74: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        75: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        76: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        77: { lcd_a0, data_tx }         = { bit_dat, 127 };
        78: { lcd_a0, data_tx }         = { bit_cmd, 8'h2B };
        79: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        80: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        81: { lcd_a0, data_tx }         = { bit_dat, 8'h00 };
        82: { lcd_a0, data_tx }         = { bit_dat, 159 };
        83: { lcd_a0, data_tx }         = { bit_cmd, 8'h2C };
        endcase

        if (i < 83) begin
            i                           = i + 1;
        end else begin
            data_tx                     = 8'hcc;
        end

        data_tx                         = {
            data_tx[7], data_tx[6], data_tx[5], data_tx[4], 
            data_tx[3], data_tx[2], data_tx[1], data_tx[0]
        };
        tx_start                        = ~tx_start;
        wait_tx                         = 1;
        
    end
    step_ini4: begin
        
    end
    endcase
end

endmodule