set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
# MC02 boots from two S25FL128S devices wired as an 8-bit parallel SPI bank.
# These settings match the board vendor's persistent-flash reference design.
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-2 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property PACKAGE_PIN AK17 [get_ports sys_clk_p]
set_property PACKAGE_PIN AK16 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {sys_clk_p sys_clk_n}]
# ClkGen.xdc already creates the 300 MHz input clock. Do not redeclare it here.

set_property PACKAGE_PIN P6 [get_ports gtrefclk_p]
set_property PACKAGE_PIN P5 [get_ports gtrefclk_n]
create_clock -name gtrefclk -period 6.400 [get_ports gtrefclk_p]

# MC02 SFP+1 is GTH channel X0Y14: TX J4/J3, RX H2/H1.
# Constraining RXP selects the complete transceiver channel, as in the vendor demo.
set_property PACKAGE_PIN H2 [get_ports sfp1_rxp]
set_property PACKAGE_PIN AG10 [get_ports sfp1_tx_disable]
set_property IOSTANDARD LVCMOS33 [get_ports sfp1_tx_disable]

# OV5640 CAM1 on the 120-pin video extension board, Bank 67/68 at 1.8 V.
set_property PACKAGE_PIN A20 [get_ports cam_d[7]]
set_property PACKAGE_PIN B22 [get_ports cam_d[6]]
set_property PACKAGE_PIN B21 [get_ports cam_d[5]]
set_property PACKAGE_PIN C22 [get_ports cam_d[4]]
set_property PACKAGE_PIN C21 [get_ports cam_d[3]]
set_property PACKAGE_PIN D23 [get_ports cam_d[2]]
set_property PACKAGE_PIN C23 [get_ports cam_d[1]]
set_property PACKAGE_PIN A24 [get_ports cam_d[0]]
set_property PACKAGE_PIN B20 [get_ports cam_pclk]
set_property PACKAGE_PIN B24 [get_ports cam_href]
set_property PACKAGE_PIN A25 [get_ports cam_vsync]
set_property PACKAGE_PIN H18 [get_ports cam_sda]
set_property PACKAGE_PIN J19 [get_ports cam_scl]
set_property PACKAGE_PIN F25 [get_ports cam_rst_n]
set_property PACKAGE_PIN H19 [get_ports cam_pwdn]

set_property IOSTANDARD LVCMOS18 [get_ports {cam_d[*] cam_pclk cam_href cam_vsync}]
set_property IOSTANDARD LVCMOS18 [get_ports {cam_sda cam_scl cam_rst_n cam_pwdn}]

# Four board push-buttons: color, grayscale, binary threshold, invert.
set_property PACKAGE_PIN R26 [get_ports algorithm_button[0]]
set_property PACKAGE_PIN T24 [get_ports algorithm_button[1]]
set_property PACKAGE_PIN T25 [get_ports algorithm_button[2]]
set_property PACKAGE_PIN T27 [get_ports algorithm_button[3]]
set_property IOSTANDARD LVCMOS18 [get_ports {algorithm_button[*]}]
set_property PULLDOWN true [get_ports {algorithm_button[*]}]

# MC02 exposes one three-channel RGB indicator. Each mode has a unique color.
set_property PACKAGE_PIN AM12 [get_ports algorithm_led[0]]
set_property PACKAGE_PIN AN12 [get_ports algorithm_led[1]]
set_property PACKAGE_PIN AP11 [get_ports algorithm_led[2]]
set_property IOSTANDARD LVCMOS33 [get_ports {algorithm_led[*]}]

# 1080p RGB565 mode uses an 84 MHz source-synchronous DVP pixel clock.
create_clock -name cam_pclk -period 11.905 [get_ports cam_pclk]
# OV5640 changes DVP data/control on the inactive (falling) PCLK edge; allow
# 1.5 ns sensor/board delay and retain more than 4 ns before rising-edge capture.
set_input_delay -clock cam_pclk -clock_fall -max 1.500 \
    [get_ports {cam_d[*] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -clock_fall -min 0.200 \
    [get_ports {cam_d[*] cam_href cam_vsync}]
set_clock_groups -asynchronous \
    -group [get_clocks cam_pclk] \
    -group [get_clocks -filter {NAME != cam_pclk}]

