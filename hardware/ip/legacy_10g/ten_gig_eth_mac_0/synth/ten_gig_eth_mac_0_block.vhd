-------------------------------------------------------------------------------
-- File       : ten_gig_eth_mac_0_block.vhd  
-- Author     : Xilinx Inc.
-------------------------------------------------------------------------------
-- Description: This is the block level vhdl code for the 
-- Ten Gigabit Ethernet MAC, where the MAC core is instanced. This file may 
-- also contain the physical interface instance for 32bit XGMII.
-------------------------------------------------------------------------------
-- (c) Copyright 2001-2014 Xilinx, Inc. All rights reserved.
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
-- 
-- 
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity ten_gig_eth_mac_0_block is
  port(
    tx_clk0                            : in  std_logic;
    reset                              : in  std_logic;
    tx_axis_aresetn                    : in std_logic;
    tx_axis_tdata                      : in std_logic_vector(63 downto 0);
    tx_axis_tkeep                      : in std_logic_vector(7 downto 0);
    tx_axis_tready                     : out std_logic; 
    tx_axis_tvalid                     : in std_logic;
    tx_axis_tlast                      : in std_logic;
    tx_axis_tuser                      : in std_logic_vector(0 downto 0);
    tx_ifg_delay                       : in std_logic_vector(7 downto 0);
    tx_statistics_vector               : out std_logic_vector(25 downto 0);
    tx_statistics_valid                : out std_logic;
    pause_val                          : in  std_logic_vector(15 downto 0);
    pause_req                          : in  std_logic;
    rx_axis_aresetn                    : in std_logic;
    rx_axis_tdata                      : out std_logic_vector(63 downto 0);
    rx_axis_tkeep                      : out std_logic_vector(7 downto 0);
    rx_axis_tvalid                     : out std_logic;
    rx_axis_tuser                      : out std_logic;
    rx_axis_tlast                      : out std_logic;
    rx_statistics_vector               : out std_logic_vector(29 downto 0);
    rx_statistics_valid                : out std_logic;
    tx_configuration_vector            : in std_logic_vector(79 downto 0);
    rx_configuration_vector            : in std_logic_vector(79 downto 0);
    status_vector                      : out std_logic_vector(2 downto 0);
    tx_dcm_locked                      : in  std_logic;
    xgmii_txd                          : out std_logic_vector(63 downto 0); -- Transmitted data
    xgmii_txc                          : out std_logic_vector(7 downto 0); -- Transmitted control
    rx_clk0                            : in std_logic;
    rx_dcm_locked                      : in std_logic;
    xgmii_rxd                          : in  std_logic_vector(63 downto 0); -- Received data
    xgmii_rxc                          : in  std_logic_vector(7 downto 0));  -- received control
end ten_gig_eth_mac_0_block;

architecture wrapper of ten_gig_eth_mac_0_block is
  
  -----------------------------------------------------------------------------
  -- Component Declaration for XGMAC (the 10Gb/E MAC core).
  ----------------------------------------------------------------------------- 
  component ten_gig_eth_mac_0_core_top
  generic (
    c_has_wan_support                  : boolean := true;
    c_family                           : string := "kintex7";
    c_has_stats                        : boolean := true;
    c_has_management                   : boolean := true;
    c_1588                             : integer := 0;
    c_pfc                              : integer := 0;
    c_rx_vec_width                     : integer := 79;
    c_tx_vec_width                     : integer := 79;
    c_s_axi_addr_width                 : integer := 11);
  port (
    reset                              : in  std_logic;
    tx_axis_aresetn                    : in std_logic;
    tx_axis_tdata                      : in std_logic_vector(63 downto 0);
    tx_axis_tkeep                      : in std_logic_vector(7 downto 0);
    tx_axis_tready                     : out std_logic;
    tx_axis_tvalid                     : in std_logic;
    tx_axis_tlast                      : in std_logic;
    tx_axis_tuser                      : in std_logic_vector(127 downto 0);
    tx_ifg_delay                       : in std_logic_vector(7 downto 0);
    tx_ts_axis_tdata                   : out std_logic_vector(127 downto 0);
    tx_ts_axis_tvalid                  : out std_logic;
    tx_statistics_vector               : out std_logic_vector(26 downto 0);
    tx_statistics_valid                : out std_logic;
    tx_pause_tvalid                    : in  std_logic;
    tx_pause_tdata                     : in  std_logic_vector(15 downto 0);
    tx_pfc_p0_tvalid                   : in  std_logic;
    tx_pfc_p1_tvalid                   : in  std_logic;
    tx_pfc_p2_tvalid                   : in  std_logic;
    tx_pfc_p3_tvalid                   : in  std_logic;
    tx_pfc_p4_tvalid                   : in  std_logic;
    tx_pfc_p5_tvalid                   : in  std_logic;
    tx_pfc_p6_tvalid                   : in  std_logic;
    tx_pfc_p7_tvalid                   : in  std_logic;    
    rx_pfc_p0_tvalid                   : out std_logic;
    rx_pfc_p1_tvalid                   : out std_logic;
    rx_pfc_p2_tvalid                   : out std_logic;
    rx_pfc_p3_tvalid                   : out std_logic;
    rx_pfc_p4_tvalid                   : out std_logic;
    rx_pfc_p5_tvalid                   : out std_logic;
    rx_pfc_p6_tvalid                   : out std_logic;
    rx_pfc_p7_tvalid                   : out std_logic;
    rx_pfc_p0_tready                   : in std_logic;
    rx_pfc_p1_tready                   : in std_logic;
    rx_pfc_p2_tready                   : in std_logic;
    rx_pfc_p3_tready                   : in std_logic;
    rx_pfc_p4_tready                   : in std_logic;
    rx_pfc_p5_tready                   : in std_logic;
    rx_pfc_p6_tready                   : in std_logic;
    rx_pfc_p7_tready                   : in std_logic;    
    rx_axis_aresetn                    : in std_logic;
    rx_axis_tdata                      : out std_logic_vector(63 downto 0);
    rx_axis_tkeep                      : out std_logic_vector(7 downto 0);
    rx_axis_tvalid                     : out std_logic;
    rx_axis_tuser                      : out std_logic;
    rx_axis_tlast                      : out std_logic;
    rx_ts_axis_tdata                   : out std_logic_vector(127 downto 0);
    rx_ts_axis_tvalid                  : out std_logic;
    rx_statistics_vector               : out std_logic_vector(30 downto 0);
    rx_statistics_valid                : out std_logic;
    s_axi_aclk                         : in  std_logic;
    s_axi_aresetn                      : in  std_logic;
    s_axi_awaddr                       : in  std_logic_vector(10 downto 0);
    s_axi_awvalid                      : in  std_logic;
    s_axi_awready                      : out std_logic;
    s_axi_wdata                        : in  std_logic_vector(31 downto 0);
    s_axi_wvalid                       : in  std_logic;
    s_axi_wready                       : out std_logic;
    s_axi_bresp                        : out std_logic_vector(1 downto 0);
    s_axi_bvalid                       : out std_logic;
    s_axi_bready                       : in  std_logic;
    s_axi_araddr                       : in  std_logic_vector(10 downto 0);
    s_axi_arvalid                      : in  std_logic;
    s_axi_arready                      : out std_logic;
    s_axi_rdata                        : out std_logic_vector(31 downto 0);
    s_axi_rresp                        : out std_logic_vector(1 downto 0);
    s_axi_rvalid                       : out std_logic;
    s_axi_rready                       : in  std_logic;
    mdio_tristate                      : out  std_logic;
    mdio_out                           : out std_logic;
    mdio_in                            : in std_logic;
    mdc                                : out  std_logic;
    xgmacint                           : out std_logic;
    tx_configuration_vector            : in std_logic_vector(79 downto 0);
    rx_configuration_vector            : in std_logic_vector(79 downto 0);
    link_status                        : out std_logic_vector(2 downto 0);
    systemtimer_s_field                : in std_logic_vector(47 downto 0);
    systemtimer_ns_field               : in std_logic_vector(31 downto 0);
    correction_timer                   : in std_logic_vector(63 downto 0);

    tx_clk                             : in  std_logic;
    tx_dcm_lock                        : in  std_logic;
    xgmii_txd                          : out std_logic_vector(63 downto 0);
    xgmii_txc                          : out std_logic_vector(7 downto 0);
    rx_clk                             : in  std_logic;
    rx_clk_enable                      : in  std_logic;
    rx_dcm_lock                        : in  std_logic;
    xgmii_rxd                          : in  std_logic_vector(63 downto 0); 
    xgmii_rxc                          : in  std_logic_vector(7 downto 0);
    rxphy_ts_align                     : in  std_logic;
    txphy_async_gb_latency             : in  std_logic_vector(15 downto 0);
    rxphy_s_field                      : in  std_logic_vector(47 downto 0);
    rxphy_ns_field                     : in  std_logic_vector(35 downto 0);
    rxphy_correction_timer             : in  std_logic_vector(63 downto 0)
  );
  end component;


  -----------------------------------------------------------------------------
  -- Internal Signal Declaration for XGMAC (the 10Gb/E MAC core).
  ------------------------------------------------------------------------------  
  signal reset_terms_tx                : std_logic;
  signal reset_terms_rx                : std_logic;
  signal rx_clk0_int                   : std_logic;
  signal rx_clk0_from_if               : std_logic;
  signal rx_dcm_locked_int             : std_logic;  -- Locked signal from RX DCM


  
  signal tx_configuration_vector_core  : std_logic_vector(79 downto 0);
  signal rx_configuration_vector_core  : std_logic_vector(79 downto 0);

  signal tx_axis_tuser_int             : std_logic_vector(127 downto 0);
  signal rx_statistics_vector_int      : std_logic_vector(30 downto 0);
  signal tx_statistics_vector_int      : std_logic_vector(26 downto 0);

begin

  ------------------------------
  -- Instantiate the XGMAC core
  ------------------------------
  ten_gig_eth_mac_0_core : ten_gig_eth_mac_0_core_top
    generic map (
      C_HAS_WAN_SUPPORT                => false,
      C_FAMILY                         => "kintexu",
      C_HAS_STATS                      => false,
      C_HAS_MANAGEMENT                 => false,
      C_1588                           => 0,
      C_PFC                            => 0,
      C_RX_VEC_WIDTH                   => 79,
      C_TX_VEC_WIDTH                   => 79,
      C_S_AXI_ADDR_WIDTH               => 11)
    port map (
      reset                            => reset,
      tx_axis_aresetn                  => tx_axis_aresetn,
      tx_axis_tdata                    => tx_axis_tdata,  
      tx_axis_tkeep                    => tx_axis_tkeep,
      tx_axis_tready                   => tx_axis_tready,
      tx_axis_tvalid                   => tx_axis_tvalid,
      tx_axis_tlast                    => tx_axis_tlast,
      tx_axis_tuser                    => tx_axis_tuser_int,
      tx_ifg_delay                     => tx_ifg_delay,
      tx_ts_axis_tdata                 => open,
      tx_ts_axis_tvalid                => open,
      tx_statistics_vector             => tx_statistics_vector_int,
      tx_statistics_valid              => tx_statistics_valid,
      tx_pause_tdata                   => pause_val,
      tx_pause_tvalid                  => pause_req,
      tx_pfc_p0_tvalid                 => '0',
      tx_pfc_p1_tvalid                 => '0',
      tx_pfc_p2_tvalid                 => '0',
      tx_pfc_p3_tvalid                 => '0',
      tx_pfc_p4_tvalid                 => '0',
      tx_pfc_p5_tvalid                 => '0',
      tx_pfc_p6_tvalid                 => '0',
      tx_pfc_p7_tvalid                 => '0',
      rx_pfc_p0_tvalid                 => open,
      rx_pfc_p1_tvalid                 => open,
      rx_pfc_p2_tvalid                 => open,
      rx_pfc_p3_tvalid                 => open,
      rx_pfc_p4_tvalid                 => open,
      rx_pfc_p5_tvalid                 => open,
      rx_pfc_p6_tvalid                 => open,
      rx_pfc_p7_tvalid                 => open,
      rx_pfc_p0_tready                 => '0',
      rx_pfc_p1_tready                 => '0',
      rx_pfc_p2_tready                 => '0',
      rx_pfc_p3_tready                 => '0',
      rx_pfc_p4_tready                 => '0',
      rx_pfc_p5_tready                 => '0',
      rx_pfc_p6_tready                 => '0',
      rx_pfc_p7_tready                 => '0',    
      rx_axis_aresetn                  => rx_axis_aresetn,
      rx_axis_tdata                    => rx_axis_tdata,
      rx_axis_tvalid                   => rx_axis_tvalid,
      rx_axis_tuser                    => rx_axis_tuser,
      rx_axis_tlast                    => rx_axis_tlast,
      rx_axis_tkeep                    => rx_axis_tkeep,
      rx_ts_axis_tdata                 => open,
      rx_ts_axis_tvalid                => open,
      rx_statistics_vector             => rx_statistics_vector_int,
      rx_statistics_valid              => rx_statistics_valid,
      s_axi_aclk                       => '0',
      s_axi_aresetn                    => '1',
      s_axi_awaddr                     => (others => '0'),
      s_axi_awvalid                    => '0',
      s_axi_awready                    => open,
      s_axi_wdata                      => (others => '0'),
      s_axi_wvalid                     => '0',
      s_axi_wready                     => open,
      s_axi_bresp                      => open,
      s_axi_bvalid                     => open,
      s_axi_bready                     => '0',
      s_axi_araddr                     => (others => '0'),
      s_axi_arvalid                    => '0',
      s_axi_arready                    => open,
      s_axi_rdata                      => open,
      s_axi_rresp                      => open,
      s_axi_rvalid                     => open,
      s_axi_rready                     => '0',
      mdio_tristate                    => open,
      mdio_out                         => open,
      mdio_in                          => '0',
      mdc                              => open,
      xgmacint                         => open,
      tx_configuration_vector          => tx_configuration_vector_core,
      rx_configuration_vector          => rx_configuration_vector_core,
      link_status                      => status_vector,
      systemtimer_s_field              => (others => '0'),
      systemtimer_ns_field             => (others => '0'),
      correction_timer                 => (others => '0'),
      tx_clk                           => tx_clk0,
      tx_dcm_lock                      => tx_dcm_locked,
      xgmii_txd                        => xgmii_txd,
      xgmii_txc                        => xgmii_txc,
      rx_clk                           => rx_clk0_int,
      rx_clk_enable                    => '1',
      rx_dcm_lock                      => rx_dcm_locked_int,
      rxphy_s_field                    => (others => '0'),
      rxphy_ns_field                   => (others => '0'),
      rxphy_correction_timer           => (others => '0'),
      rxphy_ts_align                   => '0',
      txphy_async_gb_latency           => (others => '0'),
      xgmii_rxd                        => xgmii_rxd,
      xgmii_rxc                        => xgmii_rxc
   );

   tx_axis_tuser_int(127 downto 1)  <= (others => '0');
   tx_axis_tuser_int(0)             <= tx_axis_tuser(0);
   rx_statistics_vector             <= rx_statistics_vector_int(29 downto 0);
   tx_statistics_vector             <= tx_statistics_vector_int(25 downto 0);



  
   rx_clk0_int                      <= rx_clk0;

  rx_dcm_locked_int                 <= rx_dcm_locked;

-------------------------------------------------------------------------------
-- Core reset is handled here. 
-- Core is held in reset for two clock cycles after dcm(s) have
-- have locked up. DCMs going out of lock will also reset the core
-- and keep it there until the DCM has relocked.
-------------------------------------------------------------------------------


  reset_terms_tx                    <= (not tx_dcm_locked);
  reset_terms_rx                    <= (not rx_dcm_locked_int);

  -- apply the RX block reset
  rx_configuration_vector_core(0)   <= rx_configuration_vector(0) or reset_terms_rx;

  -- Flow control reset 
  -- reset rx side registers if RX DCM goes out of lock, 
  --configuration_vector_core(62)   <= configuration_vector(62) or reset_terms_rx;
  -- reset tx side registers if tx dcm goes out of lock
  --configuration_vector_core(63)   <= configuration_vector(63) or reset_terms_tx;

  -- Transmit Block Reset
  tx_configuration_vector_core(0)   <= tx_configuration_vector(0) or reset_terms_tx;
  tx_configuration_vector_core(79 downto 1) <= tx_configuration_vector(79 downto 1);
  rx_configuration_vector_core(79 downto 1) <= rx_configuration_vector(79 downto 1);


end wrapper;


