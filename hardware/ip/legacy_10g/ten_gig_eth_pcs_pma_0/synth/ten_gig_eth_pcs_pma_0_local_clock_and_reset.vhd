-------------------------------------------------------------------------------
-- Title      : Local clocking and resets                                             
-- Project    : 10GBASE-R                                                      
-------------------------------------------------------------------------------
-- File       : ten_gig_eth_pcs_pma_0_local_clock_and_reset.vhd                                          
-------------------------------------------------------------------------------
-- Description: This file contains the 10GBASE-R clocking 
-- and reset logic which cannot be shared between multiple cores                
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
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

entity  ten_gig_eth_pcs_pma_0_local_clock_and_reset is
port
(
  areset                              : in  std_logic;
  coreclk                             : in  std_logic;
  dclk                                : in  std_logic;
  txusrclk2                           : in  std_logic;
  rxoutclk                            : in  std_logic;
  sim_speedup_control                 : in  std_logic := '0';
  signal_detect                       : in  std_logic;
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
end entity ten_gig_eth_pcs_pma_0_local_clock_and_reset;

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

architecture wrapper of ten_gig_eth_pcs_pma_0_local_clock_and_reset is

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
  
  component ten_gig_eth_pcs_pma_0_sim_speedup_controller 
  generic
  (
    SYNTH_VALUE : std_logic_vector(23 downto 0);
    SIM_VALUE : std_logic_vector(23 downto 0)
  );
  port
  (
     clk : in std_logic;
     sim_speedup_control : in std_logic := '0';
     sim_speedup_value: out std_logic_vector(23 downto 0)
  );
  end component;
  
  signal coreclk_reset_tx_tmp : std_logic;
  signal coreclk_reset_tx_i : std_logic;
  signal coreclk_areset : std_logic;
  signal dclk_areset : std_logic;

  signal txreset_txusrclk2_i : std_logic;

  signal rx_resetdone_dclk : std_logic;
  signal signal_detect_dclk : std_logic;
  signal signal_detect_coreclk : std_logic;
  signal dclk_reset_rx_tmp : std_logic;
  signal coreclk_reset_rx_tmp : std_logic;
  signal coreclk_reset_rx_i : std_logic;
  
  signal rxreset_rxusrclk2_i : std_logic;
  
  signal areset_rxusrclk2_i : std_logic;
  
  signal pma_resetout_rising_rxusrclk2_i : std_logic;
  
  signal gtrxreset_rxusrclk2_i : std_logic;
  
  signal rxuserrdy_counter : std_logic_vector(23 downto 0) := x"000000";

  -- Nominal wait time of 50000 UI = 757 cyles of 156.25MHz clock
  constant RXRESETTIME_NOM : std_logic_vector(23 downto 0) := x"0002F5"; 
  -- Maximum wait time of 37x10^6 UI = 560781 cycles of 156.25MHz clock
  constant RXRESETTIME_MAX : std_logic_vector(23 downto 0) := x"088E8D"; 
  
  -- Set this according to requirements
  signal RXRESETTIME : std_logic_vector(23 downto 0);
  
  signal rxusrclk2_i : std_logic;
  
  signal rxusrclk_i : std_logic;
  
  signal rxuserrdy_i : std_logic := '0';
  

begin

  -- The simulation-only speedup controller 
  -- This will be optimised away in the final netlist
  sim_speedup_controller_inst : ten_gig_eth_pcs_pma_0_sim_speedup_controller 
  generic map
  (
    SYNTH_VALUE => RXRESETTIME_MAX,
    SIM_VALUE   => RXRESETTIME_NOM
  )
  port map
  (
    clk => coreclk,
    sim_speedup_control => sim_speedup_control,
    sim_speedup_value => RXRESETTIME
  );
  


  rxoutclk_bufg_gt_i : BUFG_GT 
  port map
  (
     I => rxoutclk,
     CE => '1',
     CEMASK=> '1',
     CLR => reset_rx_bufg_gt,
     CLRMASK => '0',
     DIV => "000",
     O => rxusrclk_i
  );

  rxusrclk <= rxusrclk_i;

  rxusrclk2_bufg_gt_i : BUFG_GT 
  port map 
  (
      I       => rxoutclk,
      CE      => '1',
      CEMASK  => '1',
      CLR     => reset_rx_bufg_gt,
      CLRMASK => '0',
      DIV     => "001",
      O       => rxusrclk2_i
  );
  rxusrclk2 <= rxusrclk2_i;

  
  coreclk_reset_tx <= coreclk_reset_tx_i;
  txreset_txusrclk2 <= txreset_txusrclk2_i;
  rxreset_rxusrclk2 <= rxreset_rxusrclk2_i;
  areset_rxusrclk2 <= areset_rxusrclk2_i;
  pma_resetout_rising_rxusrclk2 <= pma_resetout_rising_rxusrclk2_i;

  coreclk_areset_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => coreclk,
      rst      => areset,
      data_in  => '0',
      data_out => coreclk_areset
    );

  dclk_areset_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => dclk,
      rst      => areset,
      data_in  => '0',
      data_out => dclk_areset
    );

  coreclk_reset_tx_tmp <= (not(tx_resetdone) or coreclk_areset);
  
  -- Hold core in reset until everything else is ready...
  coreclk_reset_tx_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => coreclk,
      rst      => coreclk_reset_tx_tmp,
      data_in  => '0',
      data_out => coreclk_reset_tx_i
    );

  -- Create the other synchronized resets from the core reset...
    
  txreset_txusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => txusrclk2,
      rst      => coreclk_reset_tx_i,
      data_in  => '0',
      data_out => txreset_txusrclk2_i
    );

  signal_detect_coreclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer 
    generic map(
      C_NUM_SYNC_REGS => 5) 
    port map(
      clk      => coreclk,
      data_in  => signal_detect,
      data_out => signal_detect_coreclk
    );

  coreclk_reset_rx_tmp <= (not(rx_resetdone) or coreclk_areset or 
                          not(signal_detect_coreclk));

  rxresetdone_dclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer 
    generic map(
      C_NUM_SYNC_REGS => 5) 
    port map(
      clk      => dclk,
      data_in  => rx_resetdone,
      data_out => rx_resetdone_dclk
    );

  signal_detect_dclk_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer 
    generic map(
      C_NUM_SYNC_REGS => 5) 
    port map(
      clk      => dclk,
      data_in  => signal_detect,
      data_out => signal_detect_dclk
    );

  dclk_reset_rx_tmp <= (not(rx_resetdone_dclk) or dclk_areset or 
                          not(signal_detect_dclk));

  -- Hold core in reset until everything else is ready...
  coreclk_reset_rx_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => coreclk,
      rst      => coreclk_reset_rx_tmp,
      data_in  => '0',
      data_out => coreclk_reset_rx_i
    );

  -- Hold core in reset until everything else is ready...
  dclk_reset_rx_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => dclk,
      rst      => dclk_reset_rx_tmp,
      data_in  => '0',
      data_out => dclk_reset
    );

  -- Create the other synchronized reset from the core reset...
    
  rxreset_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2_i,
      rst      => coreclk_reset_rx_i,
      data_in  => '0',
      data_out => rxreset_rxusrclk2_i
    );

  -- Asynch reset synchronizers

  areset_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2_i,
      rst      => areset,
      data_in  => '0',
      data_out => areset_rxusrclk2_i
    );

  pma_resetout_rising_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2_i,
      rst      => pma_resetout_rising,
      data_in  => '0',
      data_out => pma_resetout_rising_rxusrclk2_i
    );

  gtrxreset_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2_i,
      rst      => gtrxreset,
      data_in  => '0',
      data_out => gtrxreset_rxusrclk2_i
    );

  -- Delay the assertion of RXUSERRDY by the given amount
  reset_proc3: process (rxusrclk2_i)
  begin
    if(rxusrclk2_i'event and rxusrclk2_i = '1') then
      if(qplllock_rxusrclk2 = '0' or gtrxreset_rxusrclk2_i = '1') then
        rxuserrdy_counter <= x"000000";
      elsif(not(rxuserrdy_counter = RXRESETTIME)) then
        rxuserrdy_counter    <= rxuserrdy_counter + 1;
      else
        rxuserrdy_counter   <=  rxuserrdy_counter;
      end if;
    end if;
  end process;

  reset_proc4 : process (rxusrclk2_i)
  begin
     if(rxusrclk2_i'event and rxusrclk2_i = '1') then
       if(gtrxreset_rxusrclk2_i = '1') then
          rxuserrdy_i     <= '0';
       elsif(rxuserrdy_counter = RXRESETTIME) then
         rxuserrdy_i     <=  '1';
       else
         rxuserrdy_i     <=  rxuserrdy_i;
       end if;  
     end if;
  end process;
  
  rxuserrdy <= rxuserrdy_i;
  
end wrapper;



