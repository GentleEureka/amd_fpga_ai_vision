# Implementation-only constraints. Generated clocks and inserted I/O buffers do
# not exist while the top-level synthesis netlist still contains IP black boxes.

# The 100 MHz control clock and 156.25 MHz GT reference clock come from
# independent oscillators. Reset release is passed through ASYNC_REG chains.
set_clock_groups -asynchronous \
    -group [get_clocks clk_out1_clkgen_300m_to_100m] \
    -group [get_clocks gtrefclk]

# CAM1 PCLK pin B20 cannot use a dedicated route to the selected BUFG. At only
# 24 MHz the routed path has ample timing margin; this is inherited from the
# verified 2.5G camera design and is checked in the final timing report.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF_inst/O]

# Vivado 2023.1 ten_gig_eth_pcs_pma v6.0 revision 25 selects the inverted
# TX phase-interpolator strobe by default on UltraScale GTH.  The MC02 SFP1
# lane's known-good 10GBASE-R implementation uses the non-inverted strobe.
# Keep the fresh 2023.1 IP, but match that proven board-level GT attribute.
set_property TXPI_INVSTROBE_SEL 0 [get_cells -hier -filter {REF_NAME == GTHE3_CHANNEL}]
