`timescale 1ns / 1ps

// Verilog translation of the MC02 reference 10G MAC/PCS integration.
// The instantiated PCS/PMA, MAC FIFO and clock-reset blocks are Xilinx IP
// generated files kept below ip/legacy_10g; no project-authored VHDL is used.
module ten_gig_mac_wrapper_legacy (
    input  wire        reset,
    output wire [63:0] rx_axis_tdata,
    output wire [7:0]  rx_axis_tkeep,
    output wire        rx_axis_tvalid,
    output wire        rx_axis_tlast,
    input  wire        rx_axis_tready,
    input  wire [63:0] tx_axis_tdata,
    input  wire [7:0]  tx_axis_tkeep,
    input  wire        tx_axis_tvalid,
    input  wire        tx_axis_tlast,
    output wire        tx_axis_tready,
    input  wire        pcspma_clk156,
    input  wire        pcspma_dclk,
    output wire        pcspma_txclk322,
    input  wire        pcspma_mmcm_locked_clk156,
    input  wire        pcspma_qplllock,
    input  wire        pcspma_areset_clk156,
    input  wire        pcspma_qplloutclk,
    input  wire        pcspma_qplloutrefclk,
    input  wire        pcspma_gttxreset,
    input  wire        pcspma_gtrxreset,
    input  wire        pcspma_txuserrdy,
    input  wire        pcspma_txusrclk,
    input  wire        pcspma_txusrclk2,
    input  wire        pcspma_reset_counter_done,
    output wire        pcspma_qpllreset,
    output wire        pcspma_reset_tx_bufg_gt,
    output wire        phy0_txp,
    output wire        phy0_txn,
    input  wire        phy0_rxp,
    input  wire        phy0_rxn,
    output wire        pcs_link_up,
    output wire [2:0]  mac_status,
    output wire        xgmii_data_active
);

    localparam [79:0] TX_CONFIGURATION_VECTOR = {48'h0000_0000_0000, 32'h0000_0016};
    localparam [79:0] RX_CONFIGURATION_VECTOR = {48'h0000_0000_0000, 32'h0000_0416};

    reg [535:0] configuration_vector = 536'b0;
    initial begin
        configuration_vector[399:384] = 16'h4C4B;
    end

    wire [63:0] xgmii_txd;
    wire [7:0]  xgmii_txc;
    wire [63:0] xgmii_rxd;
    wire [7:0]  xgmii_rxc;
    wire [447:0] pcs_status_vector;
    wire [7:0] pcs_core_status_unused;
    wire tx_resetdone;
    wire rx_resetdone;
    wire resetdone = tx_resetdone && rx_resetdone;
    wire mac_core_reset = !resetdone || !pcspma_mmcm_locked_clk156;
    wire mac_core_resetn = !mac_core_reset;

    wire drp_req;
    wire core_to_gt_drpen;
    wire core_to_gt_drpwe;
    wire [15:0] core_to_gt_drpaddr;
    wire [15:0] core_to_gt_drpdi;
    wire gt_drprdy;
    wire [15:0] gt_drpdo;
    wire pcs_tx_disable_unused;
    wire rxrecclk_unused;
    wire [25:0] tx_statistics_vector_unused;
    wire tx_statistics_valid_unused;
    wire [29:0] rx_statistics_vector_unused;
    wire rx_statistics_valid_unused;

    assign pcs_link_up = resetdone && pcs_status_vector[226] && pcs_status_vector[256];
    assign xgmii_data_active = (xgmii_txc != 8'hff);

    ten_gig_eth_pcs_pma_0 pcs_pma_i (
        .rxrecclk_out(rxrecclk_unused),
        .coreclk(pcspma_clk156),
        .dclk(pcspma_dclk),
        .txusrclk(pcspma_txusrclk),
        .txusrclk2(pcspma_txusrclk2),
        .areset(reset),
        .txoutclk(pcspma_txclk322),
        .areset_coreclk(pcspma_areset_clk156),
        .gttxreset(pcspma_gttxreset),
        .gtrxreset(pcspma_gtrxreset),
        .txuserrdy(pcspma_txuserrdy),
        .qpll0lock(pcspma_qplllock),
        .qpll0outclk(pcspma_qplloutclk),
        .qpll0outrefclk(pcspma_qplloutrefclk),
        .reset_counter_done(pcspma_reset_counter_done),
        .txp(phy0_txp),
        .txn(phy0_txn),
        .rxp(phy0_rxp),
        .rxn(phy0_rxn),
        .sim_speedup_control(1'b0),
        .reset_tx_bufg_gt(pcspma_reset_tx_bufg_gt),
        .qpll0reset(pcspma_qpllreset),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .configuration_vector(configuration_vector),
        .status_vector(pcs_status_vector),
        .core_status(pcs_core_status_unused),
        .tx_resetdone(tx_resetdone),
        .rx_resetdone(rx_resetdone),
        .signal_detect(1'b1),
        .tx_fault(1'b0),
        .drp_req(drp_req),
        .drp_gnt(drp_req),
        .core_to_gt_drpen(core_to_gt_drpen),
        .core_to_gt_drpwe(core_to_gt_drpwe),
        .core_to_gt_drpaddr(core_to_gt_drpaddr),
        .core_to_gt_drpdi(core_to_gt_drpdi),
        .gt_drprdy(gt_drprdy),
        .gt_drpdo(gt_drpdo),
        .gt_drpen(core_to_gt_drpen),
        .gt_drpwe(core_to_gt_drpwe),
        .gt_drpaddr(core_to_gt_drpaddr),
        .gt_drpdi(core_to_gt_drpdi),
        .core_to_gt_drprdy(gt_drprdy),
        .core_to_gt_drpdo(gt_drpdo),
        .tx_disable(pcs_tx_disable_unused),
        .pma_pmd_type(3'b111)
    );

    ten_gig_eth_mac_0_fifo_block #(
        .FIFO_SIZE(1024)
    ) mac_fifo_i (
        .tx_clk0(pcspma_clk156),
        .reset(!pcspma_mmcm_locked_clk156),
        .rx_axis_fifo_aresetn(mac_core_resetn),
        .rx_axis_mac_aresetn(mac_core_resetn),
        .rx_axis_fifo_tdata(rx_axis_tdata),
        .rx_axis_fifo_tkeep(rx_axis_tkeep),
        .rx_axis_fifo_tvalid(rx_axis_tvalid),
        .rx_axis_fifo_tlast(rx_axis_tlast),
        .rx_axis_fifo_tready(rx_axis_tready),
        .tx_axis_fifo_aresetn(mac_core_resetn),
        .tx_axis_mac_aresetn(mac_core_resetn),
        .tx_axis_fifo_tdata(tx_axis_tdata),
        .tx_axis_fifo_tkeep(tx_axis_tkeep),
        .tx_axis_fifo_tvalid(tx_axis_tvalid),
        .tx_axis_fifo_tlast(tx_axis_tlast),
        .tx_axis_fifo_tready(tx_axis_tready),
        .tx_ifg_delay(8'h00),
        .tx_statistics_vector(tx_statistics_vector_unused),
        .tx_statistics_valid(tx_statistics_valid_unused),
        .pause_val(16'h0000),
        .pause_req(1'b0),
        .rx_statistics_vector(rx_statistics_vector_unused),
        .rx_statistics_valid(rx_statistics_valid_unused),
        .tx_configuration_vector(TX_CONFIGURATION_VECTOR),
        .rx_configuration_vector(RX_CONFIGURATION_VECTOR),
        .status_vector(mac_status),
        .tx_dcm_locked(pcspma_mmcm_locked_clk156),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .rx_clk0(pcspma_clk156),
        .rx_dcm_locked(pcspma_mmcm_locked_clk156),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc)
    );

endmodule
