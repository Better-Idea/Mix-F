set_property PACKAGE_PIN E6 [get_ports reset]
set_property PACKAGE_PIN N11 [get_ports clock_50mhz]
set_property PACKAGE_PIN N13 [get_ports lcd_cs]
set_property PACKAGE_PIN N16 [get_ports lcd_reset]
set_property PACKAGE_PIN P16 [get_ports lcd_a0]
set_property PACKAGE_PIN R16 [get_ports lcd_sda]
set_property PACKAGE_PIN T15 [get_ports lcd_sck]
set_property PACKAGE_PIN P14 [get_ports lcd_led]

set_property IOSTANDARD LVCMOS33 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports clock_50mhz]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_cs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_reset]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_a0]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_sda]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_sck]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_led]

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

create_clock -period 20.000 -name clock_50mhz -waveform {0.000 10.000} [get_ports clock_50mhz]
