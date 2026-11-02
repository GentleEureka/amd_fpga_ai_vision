-------------------------------------------------------------------------------
-- Title      : Core level wrapper
-- Project    : 10GBASE-R
-------------------------------------------------------------------------------
-- File       : ten_gig_eth_pcs_pma_0.vhd
-------------------------------------------------------------------------------
-- Description: This file is a wrapper for the 10GBASE-R core.
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

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library ten_gig_eth_pcs_pma_v6_0_7;
use ten_gig_eth_pcs_pma_v6_0_7.all;

entity ten_gig_eth_pcs_pma_0 is
  port (
      dclk               : in  std_logic;
      rxrecclk_out       : out std_logic;
      coreclk             : in  std_logic;
      txusrclk           : in  std_logic;
      txusrclk2          : in  std_logic;
      txoutclk           : out std_logic;
      areset             : in  std_logic;
      areset_coreclk      : in  std_logic;
      gttxreset          : in  std_logic;
      gtrxreset          : in  std_logic;
      sim_speedup_control: in  std_logic := '0';
      txuserrdy          : in  std_logic;
      qpll0lock           : in  std_logic;
      qpll0outclk         : in  std_logic;
      qpll0outrefclk      : in  std_logic;
      qpll0reset          : out std_logic;
      reset_tx_bufg_gt    : out std_logic;
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
      pma_pmd_type     : in std_logic_vector(2 downto 0);
      tx_disable       : out std_logic);
end ten_gig_eth_pcs_pma_0;

architecture wrapper of ten_gig_eth_pcs_pma_0 is

    attribute DowngradeIPIdentifiedWarnings: string;

    attribute DowngradeIPIdentifiedWarnings of wrapper : architecture is "yes";


  component ten_gig_eth_pcs_pma_0_block is
    port (
      coreclk          : in  std_logic;
      dclk             : in  std_logic;
      rxrecclk_out     : out std_logic;
      txusrclk         : in  std_logic;
      txusrclk2        : in  std_logic;
      txoutclk         : out std_logic;
      areset           : in  std_logic;
      areset_coreclk      : in  std_logic;
      gttxreset          : in  std_logic;
      gtrxreset          : in  std_logic;
      sim_speedup_control: in  std_logic := '0';
      txuserrdy          : in  std_logic;
      qpll0lock           : in  std_logic;
      qpll0outclk         : in  std_logic;
      qpll0outrefclk      : in  std_logic;
      qpll0reset          : out std_logic;
      reset_tx_bufg_gt    : out std_logic;
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
      pma_pmd_type     : in std_logic_vector(2 downto 0);
      tx_disable       : out std_logic);
  end component;

  ATTRIBUTE CORE_GENERATION_INFO : STRING;
  ATTRIBUTE CORE_GENERATION_INFO OF wrapper : ARCHITECTURE IS "ten_gig_eth_pcs_pma_0,ten_gig_eth_pcs_pma_wrapper,{x_ipProduct=Vivado 2016.4,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=ten_gig_eth_pcs_pma,x_ipVersion=6.0,x_ipCoreRevision=7,x_ipLanguage=VHDL,x_ipSimLanguage=MIXED,x_ipLicense=ten_gig_eth_pcs_pma_basekr@2015.04(design_linking),c_family=kintexu,c_component_name=ten_gig_eth_pcs_pma_0,c_has_mdio=false,c_has_fec=false,c_has_an=false,c_is_kr=false,c_is_32bit=false,c_no_ebuff=false,c_gttype=2,c_1588=0,c_gtif_width=64,c_speed10_25=10,c_sub_core_name=ten_gig_eth_pcs_pma_0_gt,c_gt_loc=X0Y0,c_refclk=clk0,c_refclkrate=156,c_dclkrate=100.00}";
  ATTRIBUTE X_CORE_INFO : STRING;
  ATTRIBUTE X_CORE_INFO OF wrapper: ARCHITECTURE IS "ten_gig_eth_pcs_pma_wrapper,Vivado 2016.4";
begin
--
-- Instantiate the 10Gig PCS/PMA core
--
  U0 : ten_gig_eth_pcs_pma_0_block
    port map (
      coreclk => coreclk,
      dclk => dclk,
      rxrecclk_out => rxrecclk_out,
      txusrclk => txusrclk,
      txusrclk2 => txusrclk2,
      txoutclk => txoutclk,
      areset => areset,
      areset_coreclk => areset_coreclk,
      gttxreset => gttxreset,
      gtrxreset => gtrxreset,
      sim_speedup_control => sim_speedup_control,
      txuserrdy => txuserrdy,
      qpll0lock => qpll0lock,
      qpll0outclk => qpll0outclk,
      qpll0outrefclk => qpll0outrefclk,
      qpll0reset => qpll0reset,
      reset_tx_bufg_gt => reset_tx_bufg_gt,
      reset_counter_done => reset_counter_done,
      xgmii_txd => xgmii_txd,
      xgmii_txc => xgmii_txc,
      xgmii_rxd => xgmii_rxd,
      xgmii_rxc => xgmii_rxc,
      txp => txp,
      txn => txn,
      rxp => rxp,
      rxn => rxn,
      configuration_vector => configuration_vector,
      status_vector => status_vector,
      core_status => core_status,
      tx_resetdone => tx_resetdone,
      rx_resetdone => rx_resetdone,
      signal_detect => signal_detect,
      tx_fault => tx_fault,
      drp_req => drp_req,
      drp_gnt => drp_gnt,
      core_to_gt_drpen   => core_to_gt_drpen,
      core_to_gt_drpwe   => core_to_gt_drpwe,
      core_to_gt_drpaddr => core_to_gt_drpaddr,
      core_to_gt_drpdi   => core_to_gt_drpdi,
      core_to_gt_drprdy  => core_to_gt_drprdy,
      core_to_gt_drpdo   => core_to_gt_drpdo,
      gt_drpen           => gt_drpen,
      gt_drpwe           => gt_drpwe,
      gt_drpaddr         => gt_drpaddr,
      gt_drpdi           => gt_drpdi,
      gt_drprdy          => gt_drprdy,
      gt_drpdo           => gt_drpdo,
      pma_pmd_type => pma_pmd_type,
      tx_disable => tx_disable
      );
end wrapper;



