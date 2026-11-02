`timescale 1ns / 1ps

// Verilog project boundary for the board-proven MC02 SFP1 10G integration.
// Xilinx-generated support sources live under ip/legacy_10g; all logic in
// rtl/ remains Verilog as required by the V2 project language policy.
module ten_gig_eth_endpoint (
    input  wire        reset,
    input  wire        dclk,
    input  wire        gtrefclk_p,
    input  wire        gtrefclk_n,
    output wire        net_clk,
    output wire        net_reset,
    output wire        link_up,
    output wire [2:0]  mac_status,
    output wire        xgmii_data_active,
    output wire [63:0] rx_axis_tdata,
    output wire [7:0]  rx_axis_tkeep,
    output wire        rx_axis_tvalid,
    output wire        rx_axis_tlast,
    input  wire [63:0] tx_axis_tdata,
    input  wire [7:0]  tx_axis_tkeep,
    input  wire        tx_axis_tvalid,
    input  wire        tx_axis_tlast,
    output wire        tx_axis_tready,
    output wire        txp,
    output wire        txn,
    input  wire        rxp,
    input  wire        rxn
);

    wire pcspma_refclk;
    wire pcspma_txclk322;
    wire pcspma_areset_txusrclk2_unused;
    wire pcspma_areset_coreclk;
    wire pcspma_gttxreset;
    wire pcspma_gtrxreset;
    wire pcspma_txuserrdy;
    wire pcspma_txusrclk;
    wire pcspma_txusrclk2;
    wire pcspma_reset_counter_done;
    wire pcspma_qpll0reset;
    wire pcspma_qpllreset;
    wire pcspma_reset_tx_bufg_gt;
    wire pcspma_qpll0lock;
    wire pcspma_qpll0outclk;
    wire pcspma_qpll0outrefclk;

    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_sync = 4'hf;
    always @(posedge net_clk or posedge reset) begin
        if (reset || !pcspma_qpll0lock)
            reset_sync <= 4'hf;
        else
            reset_sync <= {reset_sync[2:0], 1'b0};
    end
    assign net_reset = reset_sync[3];

    ten_gig_eth_pcs_pma_0_gt_common #(
        .WRAPPER_SIM_GTRESET_SPEEDUP("TRUE")
    ) qpll_i (
        .refclk(pcspma_refclk),
        .qpllreset(pcspma_qpllreset),
        .qpll0lock(pcspma_qpll0lock),
        .qpll0outclk(pcspma_qpll0outclk),
        .qpll0outrefclk(pcspma_qpll0outrefclk)
    );

    ten_gig_eth_pcs_pma_0_shared_clock_and_reset clock_reset_i (
        .areset(reset),
        .refclk_p(gtrefclk_p),
        .refclk_n(gtrefclk_n),
        .qpll0reset(pcspma_qpll0reset),
        .refclk(pcspma_refclk),
        .coreclk(net_clk),
        .txoutclk(pcspma_txclk322),
        .qplllock(pcspma_qpll0lock),
        .reset_tx_bufg_gt(pcspma_reset_tx_bufg_gt),
        .areset_txusrclk2(pcspma_areset_txusrclk2_unused),
        .areset_coreclk(pcspma_areset_coreclk),
        .gttxreset(pcspma_gttxreset),
        .gtrxreset(pcspma_gtrxreset),
        .txuserrdy(pcspma_txuserrdy),
        .txusrclk(pcspma_txusrclk),
        .txusrclk2(pcspma_txusrclk2),
        .qpllreset(pcspma_qpllreset),
        .reset_counter_done(pcspma_reset_counter_done)
    );

    ten_gig_mac_wrapper_legacy mac_pcs_i (
        .reset(reset),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tready(1'b1),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tkeep(tx_axis_tkeep),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tready(tx_axis_tready),
        .pcspma_clk156(net_clk),
        .pcspma_dclk(dclk),
        .pcspma_txclk322(pcspma_txclk322),
        .pcspma_mmcm_locked_clk156(pcspma_qpll0lock),
        .pcspma_qplllock(pcspma_qpll0lock),
        .pcspma_areset_clk156(pcspma_areset_coreclk),
        .pcspma_qplloutclk(pcspma_qpll0outclk),
        .pcspma_qplloutrefclk(pcspma_qpll0outrefclk),
        .pcspma_gttxreset(pcspma_gttxreset),
        .pcspma_gtrxreset(pcspma_gtrxreset),
        .pcspma_txuserrdy(pcspma_txuserrdy),
        .pcspma_txusrclk(pcspma_txusrclk),
        .pcspma_txusrclk2(pcspma_txusrclk2),
        .pcspma_reset_counter_done(pcspma_reset_counter_done),
        .pcspma_qpllreset(pcspma_qpll0reset),
        .pcspma_reset_tx_bufg_gt(pcspma_reset_tx_bufg_gt),
        .phy0_txp(txp),
        .phy0_txn(txn),
        .phy0_rxp(rxp),
        .phy0_rxn(rxn),
        .pcs_link_up(link_up),
        .mac_status(mac_status),
        .xgmii_data_active(xgmii_data_active)
    );

endmodule
