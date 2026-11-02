-------------------------------------------------------------------------------
-- Title      : Block level
-- Project    : 10GBASE-R
-------------------------------------------------------------------------------
-- File       : ten_gig_eth_pcs_pma_0_block.vhd
-------------------------------------------------------------------------------
-- Description: This file is a wrapper for the 10GBASE-R core. It contains the
-- 10GBASE-R core, the transceiver and some transceiver-related logic.
-------------------------------------------------------------------------------
-- (c) Copyright 2009 - 2014 Xilinx, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and 
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library ten_gig_eth_pcs_pma_v6_0_7;
use ten_gig_eth_pcs_pma_v6_0_7.all;

library gtwizard_ultrascale_v1_6_5;
use gtwizard_ultrascale_v1_6_5.all;


entity ten_gig_eth_pcs_pma_0_block is
    port (
      dclk               : in  std_logic;
      coreclk            : in  std_logic;
      txusrclk           : in  std_logic;
      txusrclk2          : in  std_logic;
      rxrecclk_out       : out std_logic;
      txoutclk           : out std_logic;
      areset             : in  std_logic;
      areset_coreclk     : in  std_logic;
      txuserrdy          : in  std_logic;
      gttxreset          : in  std_logic;
      gtrxreset          : in  std_logic;
      sim_speedup_control: in  std_logic := '0';
      qpll0lock          : in  std_logic;
      qpll0outclk        : in  std_logic;
      qpll0outrefclk     : in  std_logic;
      qpll0reset         : out std_logic;
      reset_tx_bufg_gt   : out std_logic;
      reset_counter_done : in  std_logic;
      xgmii_txd        : in  std_logic_vector(63 downto 0);
      xgmii_txc        : in  std_logic_vector(7 downto 0);
      xgmii_rxd        : out std_logic_vector(63 downto 0);
      xgmii_rxc        : out std_logic_vector(7 downto 0);
      txp              : out std_logic;
      txn              : out std_logic;
      rxp              : in  std_logic;
      rxn              : in  std_logic;
      configuration_vector : in  std_logic_vector(535 downto 0);
      status_vector        : out std_logic_vector(447 downto 0);
      core_status      : out std_logic_vector(7 downto 0);
      tx_resetdone     : out std_logic;
      rx_resetdone     : out std_logic;
      signal_detect    : in  std_logic;
      tx_fault         : in  std_logic;
      drp_req          : out std_logic;
      drp_gnt          : in  std_logic;
      core_to_gt_drpen : out std_logic;
      core_to_gt_drpwe : out std_logic;
      core_to_gt_drpaddr : out std_logic_vector(15 downto 0);
      core_to_gt_drpdi : out std_logic_vector(15 downto 0);
      core_to_gt_drprdy: in  std_logic;
      core_to_gt_drpdo : in  std_logic_vector(15 downto 0);
      gt_drpen         : in  std_logic;
      gt_drpwe         : in  std_logic;
      gt_drpaddr       : in  std_logic_vector(15 downto 0);
      gt_drpdi         : in  std_logic_vector(15 downto 0);
      gt_drprdy        : out std_logic;
      gt_drpdo         : out std_logic_vector(15 downto 0);
      pma_pmd_type     : in  std_logic_vector(2 downto 0);
      tx_disable       : out std_logic);
end ten_gig_eth_pcs_pma_0_block;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;

architecture wrapper of ten_gig_eth_pcs_pma_0_block is

    attribute DowngradeIPIdentifiedWarnings: string;

    attribute DowngradeIPIdentifiedWarnings of wrapper : architecture is "yes";

----------------------------------------------------------------------------
-- Component Declaration for the 10GBASE-R core.
----------------------------------------------------------------------------

  component ten_gig_eth_pcs_pma_v6_0_7
    generic(
      C_HAS_MDIO                  : boolean := false;
      C_HAS_FEC                   : boolean := false;
      C_HAS_AN                    : boolean := false;
      C_IS_KR                     : boolean := false;
      C_NO_EBUFF                  : boolean := false;
      C_IS_32BIT                  : boolean := false;
      C_DP_WIDTH                  : integer := 64;
      C_SPEED10_25                : integer := 10;
      C_GTTYPE                    : integer := 2;
      C_GTIF_WIDTH                : integer := 64;
      C_REFCLKRATE                : integer := 156;
      C_1588                      : integer := 0
      );
    port(
      reset                : in  std_logic;
      areset_coreclk       : in  std_logic;
      txreset_txusrclk2    : in  std_logic;
      rxreset_rxusrclk2    : in  std_logic;
      areset_rxusrclk2     : in  std_logic;
      dclk_reset           : in  std_logic;
      pma_resetout         : out std_logic;
      pcs_resetout         : out std_logic;
      coreclk              : in  std_logic;
      txusrclk2            : in  std_logic;
      rxusrclk2            : in  std_logic;
      dclk                 : in  std_logic;
      fr_clk               : in  std_logic := '0';
      sim_speedup_control  : in  std_logic := '0';
      xgmii_txd            : in  std_logic_vector(63 downto 0);
      xgmii_txc            : in  std_logic_vector(7 downto 0);
      xgmii_rxd            : out std_logic_vector(63 downto 0);
      xgmii_rxc            : out std_logic_vector(7 downto 0);
      mdc                  : in  std_logic;
      mdio_in              : in  std_logic;
      mdio_out             : out std_logic;
      mdio_tri             : out std_logic;
      prtad                : in  std_logic_vector(4 downto 0);
      configuration_vector : in  std_logic_vector(535 downto 0);
      status_vector        : out std_logic_vector(447 downto 0);
      core_status          : out std_logic_vector(7 downto 0);
      pma_pmd_type         : in std_logic_vector(2 downto 0);
      lfreset              : in std_logic;
      systemtimer_s_field  : in std_logic_vector(47 downto 0)  := (others => '0');
      systemtimer_ns_field : in std_logic_vector(31 downto 0)  := (others => '0');
      correction_timer     : in std_logic_vector(63 downto 0)  := (others => '0');
      rxphy_s_field        : out std_logic_vector(47 downto 0) := (others => '0');
      rxphy_ns_field       : out std_logic_vector(35 downto 0) := (others => '0');
      rxphy_correction_timer : out std_logic_vector(63 downto 0) := (others => '0');
      gt_rxstartofseq      : in  std_logic;
      gt_latclk            : in  std_logic;
      txphy_async_gb_latency : out std_logic_vector(15 downto 0);
      drp_req              : out std_logic;
      drp_gnt              : in  std_logic;
      drp_den              : out std_logic;
      drp_dwe              : out std_logic;
      drp_daddr            : out std_logic_vector(15 downto 0);
      drp_di               : out std_logic_vector(15 downto 0);
      drp_drdy             : in  std_logic;
      drp_drpdo            : in  std_logic_vector(15 downto 0);
      gt_txd               : out std_logic_vector(63 downto 0);
      gt_txc               : out std_logic_vector(7 downto 0);
      gt_rxd               : in  std_logic_vector(63 downto 0);
      gt_rxc               : in  std_logic_vector(7 downto 0);
      gt_slip              : out std_logic;
      resetdone            : in  std_logic;
      signal_detect        : in  std_logic;
      tx_fault             : in  std_logic;
      tx_disable           : out std_logic;
      tx_prbs31_en         : out std_logic;
      rx_prbs31_en         : out std_logic;
      core_in_testmode     : out std_logic;
      clear_rx_prbs_err_count        : out  std_logic;
      loopback_ctrl        : out std_logic_vector(2 downto 0);
      is_eval              : out std_logic;
      gt_progdiv_reset     : out std_logic;
      an_enable            : in  std_logic;
      coeff_minus_1        : out std_logic_vector(4 downto 0);
      coeff_plus_1         : out std_logic_vector(4 downto 0);
      coeff_zero           : out std_logic_vector(6 downto 0);
      txdiffctrl           : out std_logic_vector(4 downto 0);
      training_enable      : in  std_logic;
      training_addr        : in  std_logic_vector(20 downto 0);
      training_rnw         : in  std_logic;
      training_wrdata      : in  std_logic_vector(15 downto 0);
      training_ipif_cs     : in  std_logic;
      training_drp_cs      : in  std_logic;
      training_rddata      : out std_logic_vector(15 downto 0);
      training_rdack       : out std_logic;
      training_wrack       : out std_logic);
  end component;

 --------------------------------------------------------------------------
 -- Component declaration for the GTH/YE3 transceiver container
 --------------------------------------------------------------------------
  component ten_gig_eth_pcs_pma_0_gt
  port(
    cpllpd_in : in std_logic_vector(0 downto 0);
    dmonitorout_out : out std_logic_vector(16 downto 0);
    drpaddr_in : in std_logic_vector(8 downto 0);
    drpclk_in : in std_logic_vector(0 downto 0);
    drpdi_in : in std_logic_vector(15 downto 0);
    drpdo_out : out std_logic_vector(15 downto 0);
    drpen_in : in std_logic_vector(0 downto 0);
    drprdy_out : out std_logic_vector(0 downto 0);
    drpwe_in : in std_logic_vector(0 downto 0);
    eyescandataerror_out : out std_logic_vector(0 downto 0);
    eyescanreset_in : in std_logic_vector(0 downto 0);
    eyescantrigger_in : in std_logic_vector(0 downto 0);
    gthrxn_in : in std_logic_vector(0 downto 0);
    gthrxp_in : in std_logic_vector(0 downto 0);
    gthtxn_out : out std_logic_vector(0 downto 0);
    gthtxp_out : out std_logic_vector(0 downto 0);
    gtwiz_reset_all_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_clk_freerun_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_qpll0lock_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_qpll0reset_out : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_cdr_stable_out : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_datapath_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_rx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_pll_and_datapath_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_tx_datapath_in : in std_logic_vector(0 downto 0);
    gtwiz_reset_tx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_reset_tx_pll_and_datapath_in : in std_logic_vector(0 downto 0);
    gtwiz_userclk_rx_active_in : in std_logic_vector(0 downto 0);
    gtwiz_userclk_tx_active_in : in std_logic_vector(0 downto 0);
    loopback_in : in std_logic_vector(2 downto 0);
    pcsrsvdin_in : in std_logic_vector(15 downto 0);
    qpll0clk_in : in std_logic_vector(0 downto 0);
    qpll0refclk_in : in std_logic_vector(0 downto 0);
    qpll1clk_in : in std_logic_vector(0 downto 0);
    qpll1refclk_in : in std_logic_vector(0 downto 0);
    rxbufreset_in : in std_logic_vector(0 downto 0);
    rxbufstatus_out : out std_logic_vector(2 downto 0);
    rxcdrhold_in : in std_logic_vector(0 downto 0);
    rxcdrlock_out : out std_logic_vector(0 downto 0);
    rxdata_out : out std_logic_vector(127 downto 0);
    rxdatavalid_out : out std_logic_vector(1 downto 0);
    rxdfelpmreset_in : in std_logic_vector(0 downto 0);
    rxgearboxslip_in : in std_logic_vector(0 downto 0);
    rxheader_out : out std_logic_vector(5 downto 0);
    rxheadervalid_out : out std_logic_vector(1 downto 0);
    rxlatclk_in : in std_logic_vector(0 downto 0);
    rxlpmen_in : in std_logic_vector(0 downto 0);
    rxoutclk_out : out std_logic_vector(0 downto 0);
    rxpcsreset_in : in std_logic_vector(0 downto 0);
    rxpd_in : in std_logic_vector(1 downto 0);
    rxpmareset_in : in std_logic_vector(0 downto 0);
    rxpmaresetdone_out : out std_logic_vector(0 downto 0);
    rxpolarity_in : in std_logic_vector(0 downto 0);
    rxprbscntreset_in : in std_logic_vector(0 downto 0);
    rxprbserr_out : out std_logic_vector(0 downto 0);
    rxprbslocked_out : out std_logic_vector(0 downto 0);
    rxprbssel_in : in std_logic_vector(3 downto 0);
    rxprgdivresetdone_out : out std_logic_vector(0 downto 0);
    rxrate_in : in std_logic_vector(2 downto 0);
    rxstartofseq_out : out std_logic_vector(1 downto 0);
    rxusrclk2_in : in std_logic_vector(0 downto 0);
    rxusrclk_in : in std_logic_vector(0 downto 0);
    txbufstatus_out : out std_logic_vector(1 downto 0);
    txdata_in : in std_logic_vector(127 downto 0);
    txdiffctrl_in : in std_logic_vector(3 downto 0);
    txelecidle_in : in std_logic_vector(0 downto 0);
    txheader_in : in std_logic_vector(5 downto 0);
    txinhibit_in : in std_logic_vector(0 downto 0);
    txlatclk_in : in std_logic_vector(0 downto 0);
    txoutclk_out : out std_logic_vector(0 downto 0);
    txoutclksel_in : in std_logic_vector(2 downto 0);
    txpcsreset_in : in std_logic_vector(0 downto 0);
    txpd_in : in std_logic_vector(1 downto 0);
    txpdelecidlemode_in : in std_logic_vector(0 downto 0);
    txpmareset_in : in std_logic_vector(0 downto 0);
    txpmaresetdone_out : out std_logic_vector(0 downto 0);
    txpolarity_in : in std_logic_vector(0 downto 0);
    txpostcursor_in : in std_logic_vector(4 downto 0);
    txprbsforceerr_in : in std_logic_vector(0 downto 0);
    txprbssel_in : in std_logic_vector(3 downto 0);
    txprecursor_in : in std_logic_vector(4 downto 0);
    txprgdivresetdone_out : out std_logic_vector(0 downto 0);
    txsequence_in : in std_logic_vector(6 downto 0);
    txusrclk2_in : in std_logic_vector(0 downto 0);
    txusrclk_in : in std_logic_vector(0 downto 0)
  );  end component;



  component ten_gig_eth_pcs_pma_0_local_clock_and_reset
  port
  (
     areset                              : in  std_logic;
     coreclk                             : in  std_logic;
     dclk                                : in  std_logic;
     txusrclk2                           : in  std_logic;
     rxoutclk                            : in  std_logic;
     signal_detect                       : in  std_logic;
     sim_speedup_control                 : in  std_logic := '0';
     tx_resetdone                        : in  std_logic;
     rx_resetdone                        : in  std_logic;
     pma_resetout_rising                 : in  std_logic;
     qplllock_rxusrclk2                  : in  std_logic;
     gtrxreset                           : in  std_logic;
     reset_rx_bufg_gt                    : in  std_logic;
     coreclk_reset_tx                    : out std_logic;
     txreset_txusrclk2                   : out std_logic;
     rxreset_rxusrclk2                   : out std_logic;
     dclk_reset                          : out std_logic;
     areset_rxusrclk2                    : out std_logic;
     pma_resetout_rising_rxusrclk2       : out std_logic;
     rxuserrdy                           : out std_logic;
     rxusrclk                            : out std_logic;
     rxusrclk2                           : out std_logic
  );
  end component;

  component ten_gig_eth_pcs_pma_0_ff_synchronizer
  generic
  (
    C_NUM_SYNC_REGS : integer := 3
  );
  port
  (
    clk : in std_logic;
    data_in : in std_logic;
    data_out : out std_logic
  );
  end component;

  component ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
  generic
  (
    C_NUM_SYNC_REGS : integer := 3;
    C_RVAL : std_logic := '0'
  );
  port
  (
    clk : in std_logic;
    rst : in std_logic;
    data_in : in std_logic;
    data_out : out std_logic
  );
  end component;

  component ten_gig_eth_pcs_pma_0_cable_pull_logic
  port (
    coreclk                             : in  std_logic;
    rxusrclk2                           : in  std_logic;
    areset_rxusrclk2                    : in  std_logic;
    pma_resetout_rising_rxusrclk2       : in  std_logic;
    gt0_rxresetdone_i_reg_rxusrclk2     : in  std_logic;
    gearboxslip                         : in  std_logic;
    rx_sample_in                        : in  std_logic_vector(3 downto 0);
    cable_pull_reset_rising_reg         : out std_logic;
    cable_unpull_reset_rising_reg       : out std_logic;
    cable_is_pulled                     : out std_logic);
  end component;
----------------------------------------------------------------------------
-- Signal declarations.
---------------------------------------------------------------------------

  signal gt_txd : std_logic_vector(63 downto 0);
  signal gt_txc : std_logic_vector(7 downto 0);
  signal gt_rxd : std_logic_vector(63 downto 0);
  signal gt_rxc : std_logic_vector(7 downto 0);
  signal gt_rxd_d1 : std_logic_vector(63 downto 0);
  signal gt_rxc_d1 : std_logic_vector(7 downto 0);
  signal tx_prbs31_en : std_logic;
  signal rx_prbs31_en : std_logic;

  signal pma_resetout : std_logic;
  signal pcs_resetout : std_logic;

  signal gt0_clear_rx_prbs_err_count_i : std_logic;
  signal gt0_rxprbssel_i : std_logic_vector(2 downto 0);
  signal gt0_txprbssel_i : std_logic_vector(2 downto 0);
  signal gt0_rxgearboxslip_i : std_logic;
  signal gt0_loopback_i : std_logic_vector(2 downto 0);


  signal rxusrclk : std_logic;
  signal rxusrclk2 : std_logic;

  signal gt0_txresetdone_i : std_logic;
  signal gt0_rxresetdone_i : std_logic;

  signal gt0_rxresetdone_i_reg_rxusrclk2 : std_logic := '0';

  signal gt0_txresetdone_i_reg : std_logic;
  signal gt0_rxresetdone_i_reg : std_logic;

  signal resetdone_int     : std_logic;

  signal gt0_txheader_i : std_logic_vector(1 downto 0);
  signal gt0_txsequence_i : std_logic_vector(6 downto 0);
  signal gt0_txdata_i : std_logic_vector(63 downto 0);
  signal gt0_rxdata_i : std_logic_vector(63 downto 0);
  signal gt0_rxheader_i : std_logic_vector(1 downto 0);
  signal gt0_rxheadervalid_i : std_logic;
  signal gt0_rxdatavalid_i : std_logic;

  signal rxoutclk : std_logic;
  signal coreclk_reset_tx : std_logic;
  signal txreset_txusrclk2 : std_logic;
  signal rxreset_rxusrclk2 : std_logic;
  signal dclk_reset : std_logic;

  signal gt0_gtrxreset_c : std_logic;
  signal gt0_gttxreset_c : std_logic;
  signal gt0_gtrxreset_i : std_logic;
  signal gt0_gttxreset_i : std_logic;
  signal pma_resetout_reg : std_logic := '0';
  signal pma_resetout_rising : std_logic;
  signal pcs_resetout_reg : std_logic := '0';
  signal pcs_resetout_rising : std_logic;
  signal qpll0lock_reg : std_logic := '0';
  signal qpll0lock_rising : std_logic;
  signal txprogdivresetdone : std_logic;
  signal rxprogdivresetdone : std_logic;
  signal rxprogdivresetdone_reg : std_logic := '0';
  signal rxprogdivresetdone_rising : std_logic;
  signal block_lock_coreclk : std_logic;
  signal core_in_testmode_coreclk : std_logic;
  signal gt0_rxpcsreset_i : std_logic;
  signal gt0_txpcsreset_i : std_logic;

  signal tx_disable_i     : std_logic;

  signal  gt0_rxbufreset_i : std_logic;
  signal  gt0_rxbufstatus_i : std_logic_vector(2 downto 0);

  signal core_status_i : std_logic_vector(7 downto 0);

  -- Aid detection of a cable being pulled
  signal cable_pull_reset_rising_reg  : std_logic;
  signal cable_is_pulled              : std_logic;

  -- Aid detection of a cable being plugged back in
  signal cable_unpull_reset_rising_reg  : std_logic;

  signal gt_latclk           : std_logic := '0';
  signal gt_eyescanreset     : std_logic := '0';
  signal gt_eyescantrigger   : std_logic := '0';
  signal gt_rxcdrhold        : std_logic := '0';
  signal gt_txprbsforceerr   : std_logic := '0';
  signal gt_txpolarity       : std_logic := '0';
  signal gt_rxpolarity       : std_logic := '0';
  signal gt_rxrate           : std_logic_vector(2 downto 0) := "000";
  signal gt_loopback         : std_logic_vector(2 downto 0) := "000";
  signal gt_txprecursor      : std_logic_vector(4 downto 0) := "00000";
  signal gt_txpostcursor     : std_logic_vector(4 downto 0) := "00000";
  signal gt_txdiffctrl       : std_logic_vector(3 downto 0) := "1110";
  signal gt_eyescandataerror : std_logic;
  signal gt_txbufstatus      : std_logic_vector(1 downto 0);
  signal gt_rxbufstatus      : std_logic_vector(2 downto 0);
  signal gt_txoutclksel      : std_logic_vector(2 downto 0) := "101";
  signal gt_txpcsreset       : std_logic := '0';
  signal gt_txpmareset       : std_logic := '0';
  signal gt_rxpmareset       : std_logic := '0';
  signal gt_rxpmaresetdone   : std_logic;
  signal gt_rxdfelpmreset    : std_logic := '0';
  signal gt_rxlpmen          : std_logic := '0';
  signal gt_pcsrsvdin        : std_logic_vector(15 downto 0) := x"0000";
  signal gt_rxprbserr        : std_logic;
  signal gt_rxprbslocked     : std_logic;
  signal gt_cpllpd           : std_logic := '1';
  signal gt_txelecidle       : std_logic := '0';
  signal gt_txpdelecidlemode : std_logic := '0';
  signal gt_rxpd             : std_logic_vector(1 downto 0) := "00";
  signal gt_txpd             : std_logic_vector(1 downto 0) := "00";
  signal gt_dmonitorout      : std_logic_vector(16 downto 0);

  signal gt_progdiv_reset          : std_logic;

  signal reset_rx_bufg_gt             : std_logic;
  signal reset_tx_bufg_gt_c           : std_logic;
  signal reset_tx_bufg_gt_reg         : std_logic := '0';
  signal reset_tx_bufg_gt_sig         : std_logic := '0';
  signal reset_tx_bufg_gt_reg_falling : std_logic;

  -- Combination of the signal_detect input and cable_is_pulled
  signal signal_detect_comb          : std_logic := '1';
  signal signal_detect_rxusrclk2     : std_logic;
  signal signal_detect_coreclk       : std_logic;


  signal tx_resetdone_int : std_logic;
  signal rx_resetdone_int : std_logic;
  signal resetdone_txusrclk2 : std_logic;
  signal gt0_rxresetdone_reg_txusrclk2 : std_logic;
  signal areset_txusrclk2 : std_logic;
  signal pma_resetout_reg_txuserclk2 : std_logic;
  signal pma_resetout_coreclk_sync : std_logic;
  signal pcs_resetout_reg_txuserclk2 : std_logic;
  signal pcs_resetout_coreclk_sync : std_logic;
  signal gtrxreset_coreclk : std_logic;
  signal qplllock_coreclk : std_logic;
  signal qplllock_txusrclk2 : std_logic;
  signal qplllock_rxusrclk2 : std_logic;
  signal qplllock_coreclk_tmp : std_logic;
  signal qplllock_txusrclk2_tmp : std_logic;
  signal qplllock_rxusrclk2_tmp : std_logic;

  signal areset_rxusrclk2                    : std_logic;
  signal pma_resetout_rising_rxusrclk2       : std_logic;
  signal gt0_rxuserrdy_i                     : std_logic;


  -- 750ms is equivalent to 117188000 cycles of coreclk (6.4ns per cycle)
  -- 117188000 in hex = x6FC25A0
  constant MASTER_WATCHDOG_TIMER_RESET : std_logic_vector(28 downto 0) := "00110111111000010010110100000";

  signal master_watchdog : std_logic_vector(28 downto 0) := MASTER_WATCHDOG_TIMER_RESET;
  signal master_watchdog_barking : std_logic;
  signal core_in_testmode : std_logic;

  signal qplllock_int : std_logic;
  signal gt0_txresetdone_reg     : std_logic := '0';
  signal gt0_txresetdone_reg1    : std_logic := '0';
  signal gt0_rxresetdone_reg     : std_logic := '0';
  signal gt0_rxresetdone_reg1    : std_logic := '0';
  signal gt0_rxresetdone_reg_dup : std_logic := '0';

  attribute DONT_TOUCH : string;
  attribute DONT_TOUCH of gt0_rxresetdone_reg : signal is "YES";
  attribute DONT_TOUCH of gt0_rxresetdone_reg_dup : signal is "YES";

  -- Signals to and from the GTH/YE3/4_CHANNEL
  signal cpllpd_in : std_logic;
  signal cpllpd_in_int : std_logic_vector(0 downto 0);
  signal dmonitorout_out : std_logic_vector(16 downto 0);
  signal drpaddr_in : std_logic_vector(8 downto 0);
  signal drpclk_in : std_logic;
  signal drpclk_in_int : std_logic_vector(0 downto 0);
  signal drpdi_in : std_logic_vector(15 downto 0);
  signal drpdo_out : std_logic_vector(15 downto 0);
  signal drpen_in : std_logic;
  signal drpen_in_int : std_logic_vector(0 downto 0);
  signal drprdy_out : std_logic;
  signal drprdy_out_int : std_logic_vector(0 downto 0);
  signal drpwe_in : std_logic;
  signal drpwe_in_int : std_logic_vector(0 downto 0);
  signal eyescandataerror_out : std_logic;
  signal eyescandataerror_out_int : std_logic_vector(0 downto 0);
  signal eyescanreset_in : std_logic;
  signal eyescanreset_in_int : std_logic_vector(0 downto 0);
  signal eyescantrigger_in : std_logic;
  signal eyescantrigger_in_int : std_logic_vector(0 downto 0);
  signal gthrxn_in : std_logic;
  signal gthrxn_in_int : std_logic_vector(0 downto 0);
  signal gthrxp_in : std_logic;
  signal gthrxp_in_int : std_logic_vector(0 downto 0);
  signal gthtxn_out : std_logic;
  signal gthtxn_out_int : std_logic_vector(0 downto 0);
  signal gthtxp_out : std_logic;
  signal gthtxp_out_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_all_in : std_logic;
  signal gtwiz_reset_all_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_clk_freerun_in : std_logic;
  signal gtwiz_reset_clk_freerun_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_qpll0lock_in : std_logic;
  signal gtwiz_reset_qpll0lock_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_qpll0reset_out : std_logic;
  signal gtwiz_reset_qpll0reset_out_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_rx_cdr_stable_out : std_logic;
  signal gtwiz_reset_rx_cdr_stable_out_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_rx_datapath_in : std_logic;
  signal gtwiz_reset_rx_datapath_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_rx_done_out : std_logic;
  signal gtwiz_reset_rx_done_out_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_rx_pll_and_datapath_in : std_logic;
  signal gtwiz_reset_rx_pll_and_datapath_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_tx_datapath_in : std_logic;
  signal gtwiz_reset_tx_datapath_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_tx_done_out : std_logic;
  signal gtwiz_reset_tx_done_out_int : std_logic_vector(0 downto 0);
  signal gtwiz_reset_tx_pll_and_datapath_in : std_logic;
  signal gtwiz_reset_tx_pll_and_datapath_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_userclk_rx_active_in : std_logic;
  signal gtwiz_userclk_rx_active_in_int : std_logic_vector(0 downto 0);
  signal gtwiz_userclk_tx_active_in : std_logic;
  signal gtwiz_userclk_tx_active_in_int : std_logic_vector(0 downto 0);
  signal loopback_in : std_logic_vector(2 downto 0);
  signal pcsrsvdin_in : std_logic_vector(15 downto 0);
  signal qpll0clk_in : std_logic;
  signal qpll0clk_in_int : std_logic_vector(0 downto 0);
  signal qpll0refclk_in : std_logic;
  signal qpll0refclk_in_int : std_logic_vector(0 downto 0);
  signal qpll1clk_in : std_logic;
  signal qpll1clk_in_int : std_logic_vector(0 downto 0);
  signal qpll1refclk_in : std_logic;
  signal qpll1refclk_in_int : std_logic_vector(0 downto 0);
  signal rxbufreset_in : std_logic;
  signal rxbufreset_in_int : std_logic_vector(0 downto 0);
  signal rxbufstatus_out : std_logic_vector(2 downto 0);
  signal rxcdrhold_in : std_logic;
  signal rxcdrhold_in_int : std_logic_vector(0 downto 0);
  signal rxcdrlock_out : std_logic;
  signal rxcdrlock_out_int : std_logic_vector(0 downto 0);
  signal rxdata_out : std_logic_vector(127 downto 0);
  signal rxdatavalid_out : std_logic_vector(1 downto 0);
  signal rxdfelpmreset_in : std_logic;
  signal rxdfelpmreset_in_int : std_logic_vector(0 downto 0);
  signal rxgearboxslip_in : std_logic;
  signal rxgearboxslip_in_int : std_logic_vector(0 downto 0);
  signal rxheader_out : std_logic_vector(5 downto 0);
  signal rxheadervalid_out : std_logic_vector(1 downto 0);
  signal rxlatclk_in : std_logic;
  signal rxlatclk_in_int : std_logic_vector(0 downto 0);
  signal rxlpmen_in : std_logic;
  signal rxlpmen_in_int : std_logic_vector(0 downto 0);
  signal rxoutclk_out : std_logic;
  signal rxoutclk_out_int : std_logic_vector(0 downto 0);
  signal rxpcsreset_in : std_logic;
  signal rxpcsreset_in_int : std_logic_vector(0 downto 0);
  signal rxpd_in : std_logic_vector(1 downto 0);
  signal rxpmareset_in : std_logic;
  signal rxpmareset_in_int : std_logic_vector(0 downto 0);
  signal rxpmaresetdone_out : std_logic;
  signal rxpmaresetdone_out_int : std_logic_vector(0 downto 0);
  signal rxpolarity_in : std_logic;
  signal rxpolarity_in_int : std_logic_vector(0 downto 0);
  signal rxprbscntreset_in : std_logic;
  signal rxprbscntreset_in_int : std_logic_vector(0 downto 0);
  signal rxprbserr_out : std_logic;
  signal rxprbserr_out_int : std_logic_vector(0 downto 0);
  signal rxprbslocked_out : std_logic;
  signal rxprbslocked_out_int : std_logic_vector(0 downto 0);
  signal rxprbssel_in : std_logic_vector(3 downto 0);
  signal rxprgdivresetdone_out : std_logic;
  signal rxprgdivresetdone_out_int : std_logic_vector(0 downto 0);
  signal rxrate_in : std_logic_vector(2 downto 0);
  signal rxstartofseq_out : std_logic_vector(1 downto 0);
  signal rxusrclk2_in : std_logic;
  signal rxusrclk2_in_int : std_logic_vector(0 downto 0);
  signal rxusrclk_in : std_logic;
  signal rxusrclk_in_int : std_logic_vector(0 downto 0);
  signal txbufstatus_out : std_logic_vector(1 downto 0);
  signal txdata_in : std_logic_vector(127 downto 0);
  signal txdiffctrl_in : std_logic_vector(3 downto 0);
  signal txelecidle_in : std_logic;
  signal txelecidle_in_int : std_logic_vector(0 downto 0);
  signal txheader_in : std_logic_vector(5 downto 0);
  signal txinhibit_in : std_logic;
  signal txinhibit_in_int : std_logic_vector(0 downto 0);
  signal txlatclk_in : std_logic;
  signal txlatclk_in_int : std_logic_vector(0 downto 0);
  signal txoutclk_out : std_logic;
  signal txoutclk_out_int : std_logic_vector(0 downto 0);
  signal txoutclksel_in : std_logic_vector(2 downto 0);
  signal txpcsreset_in : std_logic;
  signal txpcsreset_in_int : std_logic_vector(0 downto 0);
  signal txpd_in : std_logic_vector(1 downto 0);
  signal txpdelecidlemode_in : std_logic;
  signal txpdelecidlemode_in_int : std_logic_vector(0 downto 0);
  signal txpmareset_in : std_logic;
  signal txpmareset_in_int : std_logic_vector(0 downto 0);
  signal txpmaresetdone_out : std_logic;
  signal txpmaresetdone_out_int : std_logic_vector(0 downto 0);
  signal txpolarity_in : std_logic;
  signal txpolarity_in_int : std_logic_vector(0 downto 0);
  signal txpostcursor_in : std_logic_vector(4 downto 0);
  signal txprbsforceerr_in : std_logic;
  signal txprbsforceerr_in_int : std_logic_vector(0 downto 0);
  signal txprbssel_in : std_logic_vector(3 downto 0);
  signal txprecursor_in : std_logic_vector(4 downto 0);
  signal txprgdivresetdone_out : std_logic;
  signal txprgdivresetdone_out_int : std_logic_vector(0 downto 0);
  signal txsequence_in : std_logic_vector(6 downto 0);
  signal txusrclk2_in : std_logic;
  signal txusrclk2_in_int : std_logic_vector(0 downto 0);
  signal txusrclk_in : std_logic;
  signal txusrclk_in_int : std_logic_vector(0 downto 0);



begin

  rxrecclk_out <= rxusrclk2;

  reset_rx_bufg_gt <= not(rxprogdivresetdone);

  qplllock_int <= qpll0lock;

  -- Local clocking/reset block
  ten_gig_eth_pcs_pma_0_local_clock_reset_block : ten_gig_eth_pcs_pma_0_local_clock_and_reset
    port map
    (
      areset                              => areset,
      coreclk                             => coreclk,
      dclk                                => dclk,
      txusrclk2                           => txusrclk2,
      rxoutclk                            => rxoutclk,
      signal_detect                       => signal_detect,
      sim_speedup_control                 => sim_speedup_control,
      tx_resetdone                        => tx_resetdone_int,
      rx_resetdone                        => rx_resetdone_int,
      pma_resetout_rising                 => pma_resetout_rising,
      qplllock_rxusrclk2                  => qplllock_rxusrclk2,
      gtrxreset                           => gt0_gtrxreset_i,
      reset_rx_bufg_gt                    => reset_rx_bufg_gt,
      coreclk_reset_tx                    => coreclk_reset_tx,
      txreset_txusrclk2                   => txreset_txusrclk2,
      rxreset_rxusrclk2                   => rxreset_rxusrclk2,
      dclk_reset                          => dclk_reset,
      areset_rxusrclk2                    => areset_rxusrclk2,
      pma_resetout_rising_rxusrclk2       => pma_resetout_rising_rxusrclk2,
      rxuserrdy                           => gt0_rxuserrdy_i,
      rxusrclk                            => rxusrclk,
      rxusrclk2                           => rxusrclk2
    );

  rx_resetdone <= rx_resetdone_int;
  tx_resetdone <= tx_resetdone_int;


  gt_progdiv_reset <= '0';

  gtrxreset_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1')
    port map(
      clk      => coreclk,
      rst      => gtrxreset,
      data_in  => '0',
      data_out => gtrxreset_coreclk
    );

  qplllock_coreclk_tmp <= not(qplllock_int);
  qplllock_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '0')
    port map(
      clk      => coreclk,
      rst      => qplllock_coreclk_tmp,
      data_in  => '1',
      data_out => qplllock_coreclk
    );

  qplllock_txusrclk2_tmp <= not(qplllock_int);
  qplllock_txusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '0')
    port map(
      clk      => txusrclk2,
      rst      => qplllock_txusrclk2_tmp,
      data_in  => '1',
      data_out => qplllock_txusrclk2
    );

  qplllock_rxusrclk2_tmp <= not(qplllock_int);
  qplllock_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '0')
    port map(
      clk      => rxusrclk2,
      rst      => qplllock_rxusrclk2_tmp,
      data_in  => '1',
      data_out => qplllock_rxusrclk2
    );

  gt0_txresetdone_proc : process(txusrclk2)
  begin
    if(txusrclk2'event and txusrclk2 = '1') then
      gt0_txresetdone_reg  <= gt0_txresetdone_i and qplllock_txusrclk2;
--To resolve CDC-11 Critical Fan-out from launch flop to destination clock 
      gt0_txresetdone_reg1 <= gt0_txresetdone_reg;
    end if;
  end process;

  gt0_rxresetdone_proc : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      gt0_rxresetdone_reg     <= gt0_rxresetdone_i and qplllock_rxusrclk2;
--To resolve CDC-11 Critical Fan-out from launch flop to destination clock 
      gt0_rxresetdone_reg_dup <= gt0_rxresetdone_i and qplllock_rxusrclk2;
      gt0_rxresetdone_reg1    <= gt0_rxresetdone_reg;
    end if;
  end process;

  ten_gig_eth_pcs_pma_0_core : ten_gig_eth_pcs_pma_v6_0_7
    generic map(
      C_HAS_MDIO                  => false,
      C_HAS_FEC                   => false,
      C_HAS_AN                    => false,
      C_IS_KR                     => false,
      C_NO_EBUFF                  => false,
      C_IS_32BIT                  => false,
      C_DP_WIDTH                  => 64,
      C_SPEED10_25                => 10,
      C_GTTYPE                    => 2,
      C_GTIF_WIDTH                => 64,
      C_REFCLKRATE                => 156,
      C_1588                      => 0
    )
    port map (
      reset                => txreset_txusrclk2,
      areset_coreclk       => areset_txusrclk2,
      txreset_txusrclk2    => txreset_txusrclk2,
      rxreset_rxusrclk2    => rxreset_rxusrclk2,
      areset_rxusrclk2     => areset_rxusrclk2,
      dclk_reset           => dclk_reset,
      pma_resetout         => pma_resetout,
      pcs_resetout         => pcs_resetout,
      coreclk              => txusrclk2,
      txusrclk2            => txusrclk2,
      rxusrclk2            => rxusrclk2,
      dclk                 => dclk,
      fr_clk               => coreclk,
      sim_speedup_control  => sim_speedup_control,
      xgmii_txd            => xgmii_txd,
      xgmii_txc            => xgmii_txc,
      xgmii_rxd            => xgmii_rxd,
      xgmii_rxc            => xgmii_rxc,
      mdc                  => '0',
      mdio_in              => '0',
      mdio_out             => open,
      mdio_tri             => open,
      prtad                => (others => '0'),
      configuration_vector => configuration_vector,
      status_vector        => status_vector,
      core_status          => core_status_i,
      pma_pmd_type         => pma_pmd_type,
      gt_latclk            => '0',
      txphy_async_gb_latency => open,
      lfreset              => '0',
      systemtimer_s_field  => (others => '0'),
      systemtimer_ns_field => (others => '0'),
      correction_timer     => (others => '0'),
      rxphy_s_field        => open,
      rxphy_ns_field       => open,
      rxphy_correction_timer => open,
      gt_rxstartofseq      => '0',
      drp_req              => drp_req,
      drp_gnt              => drp_gnt,
      drp_den              => core_to_gt_drpen,
      drp_dwe              => core_to_gt_drpwe,
      drp_daddr            => core_to_gt_drpaddr,
      drp_di               => core_to_gt_drpdi,
      drp_drdy             => core_to_gt_drprdy,
      drp_drpdo            => core_to_gt_drpdo,
      gt_txd               => gt_txd,
      gt_txc               => gt_txc,
      gt_rxd               => gt_rxd_d1,
      gt_rxc               => gt_rxc_d1,
      gt_slip              => gt0_rxgearboxslip_i,
      resetdone            => resetdone_txusrclk2,
      signal_detect        => signal_detect_comb,
      tx_fault             => tx_fault,
      tx_disable           => tx_disable_i,
      tx_prbs31_en         => tx_prbs31_en,
      rx_prbs31_en         => rx_prbs31_en,
      core_in_testmode     => core_in_testmode,
      clear_rx_prbs_err_count        => gt0_clear_rx_prbs_err_count_i,
      loopback_ctrl        => gt0_loopback_i,
      is_eval              => open,
      gt_progdiv_reset     => open,
      an_enable            => '0',
      coeff_minus_1        => open,
      coeff_plus_1         => open,
      coeff_zero           => open,
      txdiffctrl           => open,
      training_enable      => '0',
      training_addr        => (others => '0'),
      training_rnw         => '0',
      training_wrdata      => (others => '0'),
      training_ipif_cs     => '0',
      training_drp_cs      => '0',
      training_rddata      => open,
      training_rdack       => open,
      training_wrack       => open);


  tx_disable <= tx_disable_i;

  gt0_rxresetdone_reg_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => txusrclk2,
      data_in  => gt0_rxresetdone_reg,
      data_out => gt0_rxresetdone_reg_txusrclk2
    );

  gt0_txresetdone_i_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => gt0_txresetdone_reg1,
      data_out => gt0_txresetdone_i_reg
    );

  gt0_rxresetdone_i_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => gt0_rxresetdone_reg1,
      data_out => gt0_rxresetdone_i_reg
    );

  resetdone_int <= gt0_txresetdone_i_reg and gt0_rxresetdone_i_reg;
  tx_resetdone_int <= gt0_txresetdone_i_reg;
  rx_resetdone_int <= gt0_rxresetdone_i_reg;
  resetdone_txusrclk2 <= gt0_txresetdone_reg and gt0_rxresetdone_reg_txusrclk2;


  gt0_txdata_i(0 ) <= gt_txd(63);
  gt0_txdata_i(1 ) <= gt_txd(62);
  gt0_txdata_i(2 ) <= gt_txd(61);
  gt0_txdata_i(3 ) <= gt_txd(60);
  gt0_txdata_i(4 ) <= gt_txd(59);
  gt0_txdata_i(5 ) <= gt_txd(58);
  gt0_txdata_i(6 ) <= gt_txd(57);
  gt0_txdata_i(7 ) <= gt_txd(56);
  gt0_txdata_i(8 ) <= gt_txd(55);
  gt0_txdata_i(9 ) <= gt_txd(54);
  gt0_txdata_i(10) <= gt_txd(53);
  gt0_txdata_i(11) <= gt_txd(52);
  gt0_txdata_i(12) <= gt_txd(51);
  gt0_txdata_i(13) <= gt_txd(50);
  gt0_txdata_i(14) <= gt_txd(49);
  gt0_txdata_i(15) <= gt_txd(48);
  gt0_txdata_i(16) <= gt_txd(47);
  gt0_txdata_i(17) <= gt_txd(46);
  gt0_txdata_i(18) <= gt_txd(45);
  gt0_txdata_i(19) <= gt_txd(44);
  gt0_txdata_i(20) <= gt_txd(43);
  gt0_txdata_i(21) <= gt_txd(42);
  gt0_txdata_i(22) <= gt_txd(41);
  gt0_txdata_i(23) <= gt_txd(40);
  gt0_txdata_i(24) <= gt_txd(39);
  gt0_txdata_i(25) <= gt_txd(38);
  gt0_txdata_i(26) <= gt_txd(37);
  gt0_txdata_i(27) <= gt_txd(36);
  gt0_txdata_i(28) <= gt_txd(35);
  gt0_txdata_i(29) <= gt_txd(34);
  gt0_txdata_i(30) <= gt_txd(33);
  gt0_txdata_i(31) <= gt_txd(32);
  gt0_txdata_i(32) <= gt_txd(31);
  gt0_txdata_i(33) <= gt_txd(30);
  gt0_txdata_i(34) <= gt_txd(29);
  gt0_txdata_i(35) <= gt_txd(28);
  gt0_txdata_i(36) <= gt_txd(27);
  gt0_txdata_i(37) <= gt_txd(26);
  gt0_txdata_i(38) <= gt_txd(25);
  gt0_txdata_i(39) <= gt_txd(24);
  gt0_txdata_i(40) <= gt_txd(23);
  gt0_txdata_i(41) <= gt_txd(22);
  gt0_txdata_i(42) <= gt_txd(21);
  gt0_txdata_i(43) <= gt_txd(20);
  gt0_txdata_i(44) <= gt_txd(19);
  gt0_txdata_i(45) <= gt_txd(18);
  gt0_txdata_i(46) <= gt_txd(17);
  gt0_txdata_i(47) <= gt_txd(16);
  gt0_txdata_i(48) <= gt_txd(15);
  gt0_txdata_i(49) <= gt_txd(14);
  gt0_txdata_i(50) <= gt_txd(13);
  gt0_txdata_i(51) <= gt_txd(12);
  gt0_txdata_i(52) <= gt_txd(11);
  gt0_txdata_i(53) <= gt_txd(10);
  gt0_txdata_i(54) <= gt_txd(9 );
  gt0_txdata_i(55) <= gt_txd(8 );
  gt0_txdata_i(56) <= gt_txd(7 );
  gt0_txdata_i(57) <= gt_txd(6 );
  gt0_txdata_i(58) <= gt_txd(5 );
  gt0_txdata_i(59) <= gt_txd(4 );
  gt0_txdata_i(60) <= gt_txd(3 );
  gt0_txdata_i(61) <= gt_txd(2 );
  gt0_txdata_i(62) <= gt_txd(1 );
  gt0_txdata_i(63) <= gt_txd(0 );
  gt0_txheader_i(0) <= gt_txc(1);
  gt0_txheader_i(1) <= gt_txc(0);
  gt0_txsequence_i <= '0' & gt_txc(7 downto 2);

  gt_rxd(0 ) <= gt0_rxdata_i(63);
  gt_rxd(1 ) <= gt0_rxdata_i(62);
  gt_rxd(2 ) <= gt0_rxdata_i(61);
  gt_rxd(3 ) <= gt0_rxdata_i(60);
  gt_rxd(4 ) <= gt0_rxdata_i(59);
  gt_rxd(5 ) <= gt0_rxdata_i(58);
  gt_rxd(6 ) <= gt0_rxdata_i(57);
  gt_rxd(7 ) <= gt0_rxdata_i(56);
  gt_rxd(8 ) <= gt0_rxdata_i(55);
  gt_rxd(9 ) <= gt0_rxdata_i(54);
  gt_rxd(10) <= gt0_rxdata_i(53);
  gt_rxd(11) <= gt0_rxdata_i(52);
  gt_rxd(12) <= gt0_rxdata_i(51);
  gt_rxd(13) <= gt0_rxdata_i(50);
  gt_rxd(14) <= gt0_rxdata_i(49);
  gt_rxd(15) <= gt0_rxdata_i(48);
  gt_rxd(16) <= gt0_rxdata_i(47);
  gt_rxd(17) <= gt0_rxdata_i(46);
  gt_rxd(18) <= gt0_rxdata_i(45);
  gt_rxd(19) <= gt0_rxdata_i(44);
  gt_rxd(20) <= gt0_rxdata_i(43);
  gt_rxd(21) <= gt0_rxdata_i(42);
  gt_rxd(22) <= gt0_rxdata_i(41);
  gt_rxd(23) <= gt0_rxdata_i(40);
  gt_rxd(24) <= gt0_rxdata_i(39);
  gt_rxd(25) <= gt0_rxdata_i(38);
  gt_rxd(26) <= gt0_rxdata_i(37);
  gt_rxd(27) <= gt0_rxdata_i(36);
  gt_rxd(28) <= gt0_rxdata_i(35);
  gt_rxd(29) <= gt0_rxdata_i(34);
  gt_rxd(30) <= gt0_rxdata_i(33);
  gt_rxd(31) <= gt0_rxdata_i(32);
  gt_rxd(32) <= gt0_rxdata_i(31);
  gt_rxd(33) <= gt0_rxdata_i(30);
  gt_rxd(34) <= gt0_rxdata_i(29);
  gt_rxd(35) <= gt0_rxdata_i(28);
  gt_rxd(36) <= gt0_rxdata_i(27);
  gt_rxd(37) <= gt0_rxdata_i(26);
  gt_rxd(38) <= gt0_rxdata_i(25);
  gt_rxd(39) <= gt0_rxdata_i(24);
  gt_rxd(40) <= gt0_rxdata_i(23);
  gt_rxd(41) <= gt0_rxdata_i(22);
  gt_rxd(42) <= gt0_rxdata_i(21);
  gt_rxd(43) <= gt0_rxdata_i(20);
  gt_rxd(44) <= gt0_rxdata_i(19);
  gt_rxd(45) <= gt0_rxdata_i(18);
  gt_rxd(46) <= gt0_rxdata_i(17);
  gt_rxd(47) <= gt0_rxdata_i(16);
  gt_rxd(48) <= gt0_rxdata_i(15);
  gt_rxd(49) <= gt0_rxdata_i(14);
  gt_rxd(50) <= gt0_rxdata_i(13);
  gt_rxd(51) <= gt0_rxdata_i(12);
  gt_rxd(52) <= gt0_rxdata_i(11);
  gt_rxd(53) <= gt0_rxdata_i(10);
  gt_rxd(54) <= gt0_rxdata_i(9 );
  gt_rxd(55) <= gt0_rxdata_i(8 );
  gt_rxd(56) <= gt0_rxdata_i(7 );
  gt_rxd(57) <= gt0_rxdata_i(6 );
  gt_rxd(58) <= gt0_rxdata_i(5 );
  gt_rxd(59) <= gt0_rxdata_i(4 );
  gt_rxd(60) <= gt0_rxdata_i(3 );
  gt_rxd(61) <= gt0_rxdata_i(2 );
  gt_rxd(62) <= gt0_rxdata_i(1 );
  gt_rxd(63) <= gt0_rxdata_i(0 );
  gt_rxc <= "0000" & gt0_rxheadervalid_i & gt0_rxdatavalid_i & gt0_rxheader_i(0) & gt0_rxheader_i(1);
  gt_rx_reg : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      gt_rxc_d1 <= gt_rxc;
      gt_rxd_d1 <= gt_rxd;
    end if;
  end process;

  -- The route from the GT to the fabric for this signal may be longer than the clock period
  -- so add a synchronizer
  gt0_rxresetdone_i_reg_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
  generic map(
    C_NUM_SYNC_REGS => 5)
  port map(
    clk      => rxusrclk2,
    data_in  => gt0_rxresetdone_reg_dup,
    data_out => gt0_rxresetdone_i_reg_rxusrclk2
  );

  -- Create a watchdog which samples 4 bits from the gt_rxd vector and checks that it does
  -- vary from a 1010 or 0101 or 0000 pattern. If not then there may well have been a cable pull
  -- and the gt rx side needs to be reset.
  cable_pull_logic_i : ten_gig_eth_pcs_pma_0_cable_pull_logic
  port map
  (
    coreclk => coreclk,
    rxusrclk2 => rxusrclk2,
    areset_rxusrclk2 => areset_rxusrclk2,
    pma_resetout_rising_rxusrclk2 => pma_resetout_rising_rxusrclk2,
    gt0_rxresetdone_i_reg_rxusrclk2 => gt0_rxresetdone_i_reg_rxusrclk2,
    gearboxslip => gt0_rxgearboxslip_i,
    rx_sample_in => gt_rxd(7 downto 4),
    cable_pull_reset_rising_reg => cable_pull_reset_rising_reg,
    cable_unpull_reset_rising_reg => cable_unpull_reset_rising_reg,
    cable_is_pulled => cable_is_pulled
  );

  -- Sync the sig_det signal to the rxusrclk2 domain
  signal_detect_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
  generic map(
    C_NUM_SYNC_REGS => 5)
  port map(
    clk      => rxusrclk2,
    data_in  => signal_detect,
    data_out => signal_detect_rxusrclk2
  );

  -- Create the signal_detect signal as an AND of the external signal and (not) the local cable_is_pulled
  sigdetcomb_proc: process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      signal_detect_comb <= signal_detect_rxusrclk2 and not(cable_is_pulled);
    end if;
  end process;

  core_status <= core_status_i;


  areset_txusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1')
    port map(
      clk      => txusrclk2,
      rst      => areset_coreclk,
      data_in  => '0',
      data_out => areset_txusrclk2
    );

  pma_rst_txusrclk2_proc : process(txusrclk2)
  begin
    if(txusrclk2'event and txusrclk2 = '1') then
      if(areset_txusrclk2 = '1') then
        pma_resetout_reg_txuserclk2 <= '0';
      else
        pma_resetout_reg_txuserclk2 <= pma_resetout;
      end if;
    end if;
  end process;

  pma_resetout_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1')
    port map(
      clk      => coreclk,
      rst      => pma_resetout_reg_txuserclk2,
      data_in  => '0',
      data_out => pma_resetout_coreclk_sync
    );

  pma_rst_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        pma_resetout_reg <= '0';
      else
        pma_resetout_reg <= pma_resetout_coreclk_sync;
      end if;
    end if;
  end process;

  pma_rst_reg_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        pma_resetout_rising <= '0';
      else
        pma_resetout_rising <= pma_resetout_coreclk_sync and not(pma_resetout_reg);
      end if;
    end if;
  end process;

  pcs_rst_txuserclk2_proc : process(txusrclk2)
  begin
    if(txusrclk2'event and txusrclk2 = '1') then
      if(areset_txusrclk2 = '1') then
        pcs_resetout_reg_txuserclk2 <= '0';
      else
        pcs_resetout_reg_txuserclk2 <= pcs_resetout;
      end if;
    end if;
  end process;

  pcs_resetout_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1')
    port map(
      clk      => coreclk,
      rst      => pcs_resetout_reg_txuserclk2,
      data_in  => '0',
      data_out => pcs_resetout_coreclk_sync
    );

  pcs_rst_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        pcs_resetout_reg <= '0';
      else
        pcs_resetout_reg <= pcs_resetout_coreclk_sync;
      end if;
    end if;
  end process;


  pcs_rst_reg_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        pcs_resetout_rising <= '0';
      else
        pcs_resetout_rising <= pcs_resetout_coreclk_sync and not(pcs_resetout_reg);
      end if;
    end if;
  end process;

  qpll_lock_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        qpll0lock_reg <= '0';
      else
        qpll0lock_reg <= qplllock_coreclk;
      end if;
    end if;
  end process;

  qpll0lock_rising <= qplllock_coreclk and not(qpll0lock_reg);

  rxprogdivresetdone_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        rxprogdivresetdone_reg <= '0';
      else
        rxprogdivresetdone_reg <= rxprogdivresetdone;
      end if;
    end if;
  end process;

  rxprogdivresetdone_rising <= rxprogdivresetdone and not(rxprogdivresetdone_reg);

  reset_tx_bufg_gt_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
  generic map(
    C_NUM_SYNC_REGS => 5)
  port map(
    clk      => coreclk,
    data_in  => reset_tx_bufg_gt_c,
    data_out => reset_tx_bufg_gt_sig
  );

  reset_tx_bufg_gt_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
      if(areset_coreclk = '1') then
        reset_tx_bufg_gt_reg <= '0';
      else
        reset_tx_bufg_gt_reg <= reset_tx_bufg_gt_sig;
      end if;
    end if;
  end process;

  reset_tx_bufg_gt_reg_falling <= not(reset_tx_bufg_gt_sig) and reset_tx_bufg_gt_reg;


  -- Sync the sig_det signal to the coreclk domain
  signal_detect_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
  generic map(
    C_NUM_SYNC_REGS => 5)
  port map(
    clk      => coreclk,
    data_in  => signal_detect,
    data_out => signal_detect_coreclk
  );

  -- Create a master reset watchdog which toggles GTRXRESET after 750ms of not getting to PCS Block Lock
  -- Sync the necessary signals to the free-running clock domain
  block_lock_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => core_status_i(0),
      data_out => block_lock_coreclk
    );

  core_in_testmode_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => core_in_testmode,
      data_out => core_in_testmode_coreclk
    );

  master_wdog_proc : process (coreclk)
   begin
     if(coreclk'event and coreclk = '1') then
       if(resetdone_int = '0' or block_lock_coreclk = '1' or core_in_testmode_coreclk = '1') then
         master_watchdog <= MASTER_WATCHDOG_TIMER_RESET;
       else
         master_watchdog <= master_watchdog - 1;
       end if;
     end if;
  end process;

  master_wdog_barking_proc : process(coreclk)
  begin
     if(coreclk'event and coreclk = '1') then
       if (master_watchdog = "00000000000000000000000000000") then
         master_watchdog_barking <= '1';
       else
         master_watchdog_barking <= '0';
       end if;
     end if;
  end process;

  -- Incorporate the pma_resetout_rising and cable_pull/unpull_reset_rising bits generated in code below.
  gt0_gtrxreset_c <= (pma_resetout_rising or not(signal_detect_coreclk) or master_watchdog_barking or
                      cable_pull_reset_rising_reg or cable_unpull_reset_rising_reg);
  gt0_gttxreset_c <= (pma_resetout_rising or reset_tx_bufg_gt_reg_falling);

  gtreset_proc : process(coreclk)
  begin
    if(coreclk'event and coreclk = '1') then
        gt0_gtrxreset_i <= gt0_gtrxreset_c;
        gt0_gttxreset_i <= gt0_gttxreset_c;
    end if;
  end process;

  gt0_rxpcsreset_i <= pcs_resetout_rising;
  gt0_txpcsreset_i <= pcs_resetout_rising;

  gt0_rxprbssel_i      <= rx_prbs31_en & "00";
  gt0_txprbssel_i      <= tx_prbs31_en & "00";

  -- reset the GT RX Buffer when over/underflowing
  bufresetproc: process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      if(gt0_rxbufstatus_i(2) = '1' and gt0_rxresetdone_i_reg_rxusrclk2 = '1') then
        gt0_rxbufreset_i <= '1';
      else
        gt0_rxbufreset_i <= '0';
      end if;
    end if;
  end process;


  ----------------------------- The GT Wrapper -----------------------------

  -- As generated by the GT Wizard - cut from _top level in eg design dir
  -- Use this example as a template for any updates - some signal names in
  -- port mappings may have been changed from the GT wizard output


  -- Assign signals to the GT

  drpaddr_in  <= gt_drpaddr(8 downto 0);

  drpclk_in   <= dclk;
  drpdi_in    <= gt_drpdi;
  gt_drpdo <= drpdo_out;
  drpen_in    <= gt_drpen;
  gt_drprdy  <= drprdy_out;
  drpwe_in    <= gt_drpwe;
  gthrxn_in   <= rxn;
  gthrxp_in   <= rxp;
  txn         <= gthtxn_out;
  txp         <= gthtxp_out;

  gtwiz_reset_clk_freerun_in <= dclk;
  gtwiz_reset_rx_datapath_in <= gt0_gtrxreset_i;
  gtwiz_reset_rx_pll_and_datapath_in <= '0';
  gtwiz_reset_tx_datapath_in <= gt0_gttxreset_i;
  gtwiz_reset_tx_pll_and_datapath_in <= '0';
  
  gtwiz_reset_all_in <= areset;
  gtwiz_reset_qpll0lock_in <= qpll0lock and not(gt_progdiv_reset);
  qpll0reset <= gtwiz_reset_qpll0reset_out;

  gtwiz_userclk_rx_active_in <= rxprogdivresetdone and rxpmaresetdone_out;
  gtwiz_userclk_tx_active_in <= txprogdivresetdone and txpmaresetdone_out;

  loopback_in       <= gt0_loopback_i or gt_loopback;
  qpll0clk_in       <= qpll0outclk;
  qpll0refclk_in    <= qpll0outrefclk;
  qpll1clk_in       <= '0';
  qpll1refclk_in    <= '0';
  rxbufreset_in     <= gt0_rxbufreset_i;
  gt0_rxbufstatus_i <= rxbufstatus_out;
  gt0_rxdata_i      <= rxdata_out(63 downto 0);


  rxgearboxslip_in    <= gt0_rxgearboxslip_i;

  gt0_rxheader_i      <= rxheader_out(1 downto 0);

  gt0_rxdatavalid_i   <= rxdatavalid_out(0);

  gt0_rxheadervalid_i <= rxheadervalid_out(0);
  rxoutclk      <= rxoutclk_out;
  rxpcsreset_in <= gt0_rxpcsreset_i;
  rxprbscntreset_in <= gt0_clear_rx_prbs_err_count_i;
  rxprbssel_in <= "0" & rx_prbs31_en & "0" & rx_prbs31_en;
  gt0_rxresetdone_i <= gtwiz_reset_rx_done_out;
  rxusrclk2_in <= rxusrclk2;
  rxusrclk_in  <= rxusrclk;
  txdata_in(63 downto 0)    <= gt0_txdata_i;
  txdata_in(127 downto 64)  <= X"0000000000000000";
  txheader_in(5 downto 2)  <= "0000";
  txheader_in(1 downto 0)  <= gt0_txheader_i;
  txpolarity_in <= gt_txpolarity;
  rxpolarity_in <= gt_rxpolarity;
  txprbsforceerr_in <= gt_txprbsforceerr;
  rxrate_in <= gt_rxrate;
  eyescanreset_in <= gt_eyescanreset;
  eyescantrigger_in <= gt_eyescantrigger;
  txinhibit_in <= tx_disable_i;
  rxcdrhold_in <= gt_rxcdrhold;
  txdiffctrl_in   <= gt_txdiffctrl;
  txpostcursor_in <= gt_txpostcursor;
  txprecursor_in  <= gt_txprecursor;
  rxlpmen_in <= gt_rxlpmen;
  txprogdivresetdone <= txprgdivresetdone_out;
  rxprogdivresetdone <= rxprgdivresetdone_out;
  txoutclk          <= txoutclk_out;
  txpcsreset_in     <= gt0_txpcsreset_i or gt_txpcsreset;
  txoutclksel_in    <= gt_txoutclksel;
  txprbssel_in <= "0" & tx_prbs31_en & "0" & tx_prbs31_en;
  gt0_txresetdone_i <= gtwiz_reset_tx_done_out;
  txsequence_in     <= gt0_txsequence_i;
  txusrclk2_in      <= txusrclk2;
  txusrclk_in       <= txusrclk;
  txlatclk_in       <= gt_latclk;
  rxlatclk_in       <= gt_latclk;

  gt_eyescandataerror <= eyescandataerror_out;
  gt_txbufstatus <= txbufstatus_out;
  gt_rxbufstatus <= rxbufstatus_out;
  gt_rxprbserr <= rxprbserr_out;
  gt_rxprbslocked <= rxprbslocked_out;
  txpmareset_in <= gt_txpmareset;
  rxpmareset_in <= gt_rxpmareset;
  rxdfelpmreset_in <= gt_rxdfelpmreset;
  pcsrsvdin_in <= gt_pcsrsvdin;
  gt_rxpmaresetdone <= rxpmaresetdone_out;
  gt_dmonitorout <= dmonitorout_out;
  cpllpd_in <= gt_cpllpd;
  rxpd_in <= gt_rxpd;
  txpd_in <= gt_txpd;
  txelecidle_in <= gt_txelecidle;
  txpdelecidlemode_in <= gt_txpdelecidlemode;

  reset_tx_bufg_gt   <= not(txprogdivresetdone);
  reset_tx_bufg_gt_c <= not(txprogdivresetdone);

  -- Map single bits to unit-length vectors...
  cpllpd_in_int(0) <= cpllpd_in;
  drpclk_in_int(0) <= drpclk_in;
  drpen_in_int(0) <= drpen_in;
  drprdy_out <= drprdy_out_int(0);
  drpwe_in_int(0) <= drpwe_in;
  eyescandataerror_out <= eyescandataerror_out_int(0);
  eyescanreset_in_int(0) <= eyescanreset_in;
  eyescantrigger_in_int(0) <= eyescantrigger_in;
  gthrxn_in_int(0) <= gthrxn_in;
  gthrxp_in_int(0) <= gthrxp_in;
  gthtxn_out <= gthtxn_out_int(0);
  gthtxp_out <= gthtxp_out_int(0);
  gtwiz_reset_all_in_int(0) <= gtwiz_reset_all_in;
  gtwiz_reset_clk_freerun_in_int(0) <= gtwiz_reset_clk_freerun_in;
  gtwiz_reset_qpll0lock_in_int(0) <= gtwiz_reset_qpll0lock_in;
  gtwiz_reset_qpll0reset_out <= gtwiz_reset_qpll0reset_out_int(0);
  gtwiz_reset_rx_cdr_stable_out <= gtwiz_reset_rx_cdr_stable_out_int(0);
  gtwiz_reset_rx_datapath_in_int(0) <= gtwiz_reset_rx_datapath_in;
  gtwiz_reset_rx_done_out <= gtwiz_reset_rx_done_out_int(0);
  gtwiz_reset_rx_pll_and_datapath_in_int(0) <= gtwiz_reset_rx_pll_and_datapath_in;
  gtwiz_reset_tx_datapath_in_int(0) <= gtwiz_reset_tx_datapath_in;
  gtwiz_reset_tx_done_out <= gtwiz_reset_tx_done_out_int(0);
  gtwiz_reset_tx_pll_and_datapath_in_int(0) <= gtwiz_reset_tx_pll_and_datapath_in;
  gtwiz_userclk_rx_active_in_int(0) <= gtwiz_userclk_rx_active_in;
  gtwiz_userclk_tx_active_in_int(0) <= gtwiz_userclk_tx_active_in;
  qpll0clk_in_int(0) <= qpll0clk_in;
  qpll0refclk_in_int(0) <= qpll0refclk_in;
  qpll1clk_in_int(0) <= qpll1clk_in;
  qpll1refclk_in_int(0) <= qpll1refclk_in;
  rxbufreset_in_int(0) <= rxbufreset_in;
  rxcdrhold_in_int(0) <= rxcdrhold_in;
  rxcdrlock_out <= rxcdrlock_out_int(0);
  rxdfelpmreset_in_int(0) <= rxdfelpmreset_in;
  rxgearboxslip_in_int(0) <= rxgearboxslip_in;
  rxlatclk_in_int(0) <= rxlatclk_in;
  rxlpmen_in_int(0) <= rxlpmen_in;
  rxoutclk_out <= rxoutclk_out_int(0);
  rxpcsreset_in_int(0) <= rxpcsreset_in;
  rxpmareset_in_int(0) <= rxpmareset_in;
  rxpmaresetdone_out <= rxpmaresetdone_out_int(0);
  rxpolarity_in_int(0) <= rxpolarity_in;
  rxprbscntreset_in_int(0) <= rxprbscntreset_in;
  rxprbserr_out <= rxprbserr_out_int(0);
  rxprbslocked_out <= rxprbslocked_out_int(0);
  rxprgdivresetdone_out <= rxprgdivresetdone_out_int(0);
  rxusrclk2_in_int(0) <= rxusrclk2_in;
  rxusrclk_in_int(0) <= rxusrclk_in;
  txelecidle_in_int(0) <= txelecidle_in;
  txinhibit_in_int(0) <= txinhibit_in;
  txlatclk_in_int(0) <= txlatclk_in;
  txoutclk_out <= txoutclk_out_int(0);
  txpcsreset_in_int(0) <= txpcsreset_in;
  txpdelecidlemode_in_int(0) <= txpdelecidlemode_in;
  txpmareset_in_int(0) <= txpmareset_in;
  txpmaresetdone_out <= txpmaresetdone_out_int(0);
  txpolarity_in_int(0) <= txpolarity_in;
  txprbsforceerr_in_int(0) <= txprbsforceerr_in;
  txprgdivresetdone_out <= txprgdivresetdone_out_int(0);
  txusrclk2_in_int(0) <= txusrclk2_in;
  txusrclk_in_int(0) <= txusrclk_in;


  -- Instance of GT
  ten_gig_eth_pcs_pma_0_gt_i : ten_gig_eth_pcs_pma_0_gt
  port map(
    cpllpd_in => cpllpd_in_int,
    dmonitorout_out => dmonitorout_out,
    drpaddr_in => drpaddr_in,
    drpclk_in => drpclk_in_int,
    drpdi_in => drpdi_in,
    drpdo_out => drpdo_out,
    drpen_in => drpen_in_int,
    drprdy_out => drprdy_out_int,
    drpwe_in => drpwe_in_int,
    eyescandataerror_out => eyescandataerror_out_int,
    eyescanreset_in => eyescanreset_in_int,
    eyescantrigger_in => eyescantrigger_in_int,
    gthrxn_in => gthrxn_in_int,
    gthrxp_in => gthrxp_in_int,
    gthtxn_out => gthtxn_out_int,
    gthtxp_out => gthtxp_out_int,
    gtwiz_reset_all_in => gtwiz_reset_all_in_int,
    gtwiz_reset_clk_freerun_in => gtwiz_reset_clk_freerun_in_int,
    gtwiz_reset_qpll0lock_in => gtwiz_reset_qpll0lock_in_int,
    gtwiz_reset_qpll0reset_out => gtwiz_reset_qpll0reset_out_int,
    gtwiz_reset_rx_cdr_stable_out => gtwiz_reset_rx_cdr_stable_out_int,
    gtwiz_reset_rx_datapath_in => gtwiz_reset_rx_datapath_in_int,
    gtwiz_reset_rx_done_out => gtwiz_reset_rx_done_out_int,
    gtwiz_reset_rx_pll_and_datapath_in => gtwiz_reset_rx_pll_and_datapath_in_int,
    gtwiz_reset_tx_datapath_in => gtwiz_reset_tx_datapath_in_int,
    gtwiz_reset_tx_done_out => gtwiz_reset_tx_done_out_int,
    gtwiz_reset_tx_pll_and_datapath_in => gtwiz_reset_tx_pll_and_datapath_in_int,
    gtwiz_userclk_rx_active_in => gtwiz_userclk_rx_active_in_int,
    gtwiz_userclk_tx_active_in => gtwiz_userclk_tx_active_in_int,
    loopback_in => loopback_in,
    pcsrsvdin_in => pcsrsvdin_in,
    qpll0clk_in => qpll0clk_in_int,
    qpll0refclk_in => qpll0refclk_in_int,
    qpll1clk_in => qpll1clk_in_int,
    qpll1refclk_in => qpll1refclk_in_int,
    rxbufreset_in => rxbufreset_in_int,
    rxbufstatus_out => rxbufstatus_out,
    rxcdrhold_in => rxcdrhold_in_int,
    rxcdrlock_out => rxcdrlock_out_int,
    rxdata_out => rxdata_out,
    rxdatavalid_out => rxdatavalid_out,
    rxdfelpmreset_in => rxdfelpmreset_in_int,
    rxgearboxslip_in => rxgearboxslip_in_int,
    rxheader_out => rxheader_out,
    rxheadervalid_out => rxheadervalid_out,
    rxlatclk_in => rxlatclk_in_int,
    rxlpmen_in => rxlpmen_in_int,
    rxoutclk_out => rxoutclk_out_int,
    rxpcsreset_in => rxpcsreset_in_int,
    rxpd_in => rxpd_in,
    rxpmareset_in => rxpmareset_in_int,
    rxpmaresetdone_out => rxpmaresetdone_out_int,
    rxpolarity_in => rxpolarity_in_int,
    rxprbscntreset_in => rxprbscntreset_in_int,
    rxprbserr_out => rxprbserr_out_int,
    rxprbslocked_out => rxprbslocked_out_int,
    rxprbssel_in => rxprbssel_in,
    rxprgdivresetdone_out => rxprgdivresetdone_out_int,
    rxrate_in => rxrate_in,
    rxstartofseq_out => rxstartofseq_out,
    rxusrclk2_in => rxusrclk2_in_int,
    rxusrclk_in => rxusrclk_in_int,
    txbufstatus_out => txbufstatus_out,
    txdata_in => txdata_in,
    txdiffctrl_in => txdiffctrl_in,
    txelecidle_in => txelecidle_in_int,
    txheader_in => txheader_in,
    txinhibit_in => txinhibit_in_int,
    txlatclk_in => txlatclk_in_int,
    txoutclk_out => txoutclk_out_int,
    txoutclksel_in => txoutclksel_in,
    txpcsreset_in => txpcsreset_in_int,
    txpd_in => txpd_in,
    txpdelecidlemode_in => txpdelecidlemode_in_int,
    txpmareset_in => txpmareset_in_int,
    txpmaresetdone_out => txpmaresetdone_out_int,
    txpolarity_in => txpolarity_in_int,
    txpostcursor_in => txpostcursor_in,
    txprbsforceerr_in => txprbsforceerr_in_int,
    txprbssel_in => txprbssel_in,
    txprecursor_in => txprecursor_in,
    txprgdivresetdone_out => txprgdivresetdone_out_int,
    txsequence_in => txsequence_in,
    txusrclk2_in => txusrclk2_in_int,
    txusrclk_in => txusrclk_in_int
  );


end wrapper;
