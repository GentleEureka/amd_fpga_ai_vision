-------------------------------------------------------------------------------
-- Title      : Cable Pull handling logic
-- Project    : 10GBASE-R
-------------------------------------------------------------------------------
-- File       : ten_gig_eth_pcs_pma_0_cable_pull_logic.vhd
-------------------------------------------------------------------------------
-- Description: This file contains the logic to detect Cable-Pull and Cable-
--              Reattachment
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

entity ten_gig_eth_pcs_pma_0_cable_pull_logic is
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

end ten_gig_eth_pcs_pma_0_cable_pull_logic;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

architecture wrapper of ten_gig_eth_pcs_pma_0_cable_pull_logic is

  attribute DowngradeIPIdentifiedWarnings: string;
  attribute DowngradeIPIdentifiedWarnings of wrapper : architecture is "yes";

  attribute ASYNC_REG: string;
  
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
    C_NUM_SYNC_REGS : integer := 4
  );
  port
  (
    clk : in std_logic;
    data_in : in std_logic;
    data_out : out std_logic
  );
  end component;

  -- Aid the detection of a cable/board being pulled
  constant CABLE_PULL_WATCHDOG_RESET : std_logic_vector(19 downto 0) := x"10000"; -- 64K cycles = 64K words
  constant CABLE_UNPULL_WATCHDOG_RESET : std_logic_vector(19 downto 0) := x"10000"; 

  -- Ignore the rx_sample_in immediately after a gearboxslip, to avoid possibly seeing X's in simulation
  constant GEARBOXSLIP_IGNORE_COUNT : std_logic_vector(3 downto 0) := x"F";
  signal gearboxslipignorecount : std_logic_vector(3 downto 0) := x"F";
  signal gearboxslipignore : std_logic := '0';

  signal rx_sample : std_logic_vector(3 downto 0) := "0000"; -- Used to monitor RX data for a cable pull
  signal rx_sample_prev : std_logic_vector(3 downto 0) := "0000"; -- Used to monitor RX data for a cable pull
  signal cable_pull_watchdog : std_logic_vector(19 downto 0) := CABLE_PULL_WATCHDOG_RESET;
  signal cable_pull_watchdog_event : std_logic_vector(1 downto 0) := "00"; -- Count events which suggest no cable pull
  signal cable_pull_reset : std_logic := '0';  -- This is set when the watchdog above gets to 0.
  signal cable_pull_reset_reg : std_logic;  --  This is set when the watchdog above gets to 0.
  signal cable_pull_reset_reg_reg : std_logic := '0';  
  signal cable_pull_reset_rising_int : std_logic := '0'; 
  signal cable_pull_reset_rising_reg_int : std_logic := '0'; 
  signal cable_pull_reset_rising_rxusrclk2 : std_logic;

  -- Aid the detection of a cable/board being plugged back in
  signal cable_unpull_enable : std_logic := '0'; 
  signal cable_unpull_watchdog : std_logic_vector(19 downto 0) := CABLE_UNPULL_WATCHDOG_RESET;
  signal cable_unpull_watchdog_event : std_logic_vector(10 downto 0) := "00000000000";
  signal cable_unpull_reset : std_logic := '0'; 
  signal cable_unpull_reset_reg : std_logic; 
  signal cable_unpull_reset_reg_reg : std_logic := '0'; 
  signal cable_unpull_reset_rising_int : std_logic := '0'; 
  signal cable_unpull_reset_rising_reg_int : std_logic := '0'; 
  signal cable_unpull_reset_rising_rxusrclk2 : std_logic;

begin

  -- Need to ignore the rx_sample_in data for several cycles after a gearboxslip is
  -- requested since in simulation, Xs can appear on the GT RXDATA pins, which if 
  -- sampled, propagate through the design.
  slip_ignore_proc : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then 
      if(gearboxslip = '1') then -- start ignoring
        gearboxslipignorecount <= GEARBOXSLIP_IGNORE_COUNT;
        gearboxslipignore <= '1';
      elsif(gearboxslipignorecount = x"0") then -- done with ignoring
        gearboxslipignore <= '0';
      else -- Keep counting
        gearboxslipignorecount <= gearboxslipignorecount - 1;
      end if;
    end if;
  end process slip_ignore_proc;

  -- Create a watchdog which samples 4 bits from the gt_rxd vector and checks that it does
  -- vary from a 1010 or 0101 or 0000 pattern. If not then there may well have been a cable pull
  -- and the gt rx side needs to be reset.
  cable_pull_proc : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      if(cable_pull_reset_rising_rxusrclk2 = '1') then
        cable_pull_watchdog <= CABLE_PULL_WATCHDOG_RESET; -- reset the watchdog
        cable_pull_reset <= '0';
        cable_pull_watchdog_event <= "00";
        rx_sample <= "0000";
        rx_sample_prev <= "0000";
      -- Sample 4 bits of the gt_rxd vector
      elsif(gearboxslipignore = '0') then 
        rx_sample <= rx_sample_in;
        rx_sample_prev <= rx_sample;
      end if;
      if(cable_pull_reset = '0' and cable_unpull_enable = '0' and gt0_rxresetdone_i_reg_rxusrclk2 = '1') then
        -- If those 4 bits do not look like the cable-pull behaviour, increment the event counter
        -- When NOT using RXLPM mode, the cable pull behaviour will have either 1010 or 0101 or
        -- perhaps 0000 in the sample, and not changing twice in two consecutive clock ticks.
        if(not(rx_sample = "1010") and not(rx_sample = "0101") and not(rx_sample = "0000") and not(rx_sample = rx_sample_prev)) then -- increment the event counter
          cable_pull_watchdog_event <= cable_pull_watchdog_event + 1;
        else -- we are seeing what may be a cable pull
          cable_pull_watchdog_event <= "00";
        end if;

        if(cable_pull_watchdog_event = "10") then -- Two consecutive events which look like the cable is attached
          cable_pull_watchdog <= CABLE_PULL_WATCHDOG_RESET; -- reset the watchdog
          cable_pull_watchdog_event <= "00";
        else
          cable_pull_watchdog <= cable_pull_watchdog - 1;
        end if;

        if(cable_pull_watchdog = x"00000") then
          cable_pull_reset <= '1'; -- Hit GTRXRESET!
        else
          cable_pull_reset <= '0';
        end if;
      end if;
    end if;
  end process;

  cable_pull_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => cable_pull_reset,
      data_out => cable_pull_reset_reg
    );
    
  cable_pull_proc2 : process(coreclk)
  begin
     if(coreclk'event and coreclk = '1') then
       cable_pull_reset_reg_reg <= cable_pull_reset_reg;
       cable_pull_reset_rising_int <= cable_pull_reset_reg and not(cable_pull_reset_reg_reg);
       cable_pull_reset_rising_reg_int <= cable_pull_reset_rising_int;
     end if;
  end process cable_pull_proc2;

  cable_unpull_enable_proc : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      if(areset_rxusrclk2 = '1' or pma_resetout_rising_rxusrclk2 = '1') then
        cable_unpull_enable <= '0';
      elsif(cable_pull_reset = '1') then -- Cable pull has been detected - enable cable unpull counter
        cable_unpull_enable <= '1';
      elsif(cable_unpull_reset = '1') then -- Cable has been detected as being plugged in again
        cable_unpull_enable <= '0';
      else
        cable_unpull_enable <= cable_unpull_enable;
      end if;
    end if;
  end process cable_unpull_enable_proc;

  -- Look for data on the line which does NOT look like the cable is still pulled
  -- a set of 1024 non-1010 or 0101 or 0000 samples within 64k words suggests that the cable is in.
  cable_unpull_proc : process(rxusrclk2)
  begin
    if(rxusrclk2'event and rxusrclk2 = '1') then
      if(cable_unpull_reset_rising_rxusrclk2 = '1') then
        cable_unpull_reset <= '0';
        cable_unpull_watchdog_event <= "00000000000"; -- reset the event counter
        cable_unpull_watchdog <= CABLE_UNPULL_WATCHDOG_RESET; -- reset the watchdog window
      elsif(cable_unpull_reset = '0' and cable_unpull_enable = '1' and gt0_rxresetdone_i_reg_rxusrclk2 = '1') then
        -- If the 4 bits do not look like the cable-pull behaviour, increment the event counter
        if(not(rx_sample = "1010") and not(rx_sample = "0101") and not(rx_sample = "0000") and not(rx_sample = rx_sample_prev)) then  -- increment the event counter
          cable_unpull_watchdog_event <= cable_unpull_watchdog_event + 1;
        end if;
        if(cable_unpull_watchdog_event(10) = '1') then -- Detected 1k 'valid' rx data words within 64k words
          cable_unpull_reset <= '1'; -- Hit GTRXRESET again!
          cable_unpull_watchdog <= CABLE_UNPULL_WATCHDOG_RESET; -- reset the watchdog window
        else
          cable_unpull_watchdog <= cable_unpull_watchdog - 1;
        end if;

        if(cable_unpull_watchdog = x"00000") then
          cable_unpull_watchdog <= CABLE_UNPULL_WATCHDOG_RESET; -- reset the watchdog window
          cable_unpull_watchdog_event <= "00000000000"; -- reset the event counter
        end if;
      end if;
    end if;
  end process cable_unpull_proc;

  cable_unpull_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer
    generic map(
      C_NUM_SYNC_REGS => 5)
    port map(
      clk      => coreclk,
      data_in  => cable_unpull_reset,
      data_out => cable_unpull_reset_reg
    );
    
  cable_unpull_proc2 : process(coreclk)
  begin
     if(coreclk'event and coreclk = '1') then
       cable_unpull_reset_reg_reg <= cable_unpull_reset_reg;
       cable_unpull_reset_rising_int <= cable_unpull_reset_reg and not(cable_unpull_reset_reg_reg);
       cable_unpull_reset_rising_reg_int <= cable_unpull_reset_rising_int;
     end if;
  end process cable_unpull_proc2;

  -- Create the local cable_is_pulled signal
  cable_is_pulled <= cable_unpull_enable;
  
  -- Wire-out the internal signals
  cable_pull_reset_rising_reg <= cable_pull_reset_rising_reg_int;
  cable_unpull_reset_rising_reg <= cable_unpull_reset_rising_reg_int;

  cable_pull_reset_rising_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2,
      rst      => cable_pull_reset_rising_int,
      data_in  => '0',
      data_out => cable_pull_reset_rising_rxusrclk2
    );

  cable_unpull_reset_rising_rxusrclk2_sync_i : ten_gig_eth_pcs_pma_0_ff_synchronizer_rst 
    generic map(
      C_NUM_SYNC_REGS => 5,
      C_RVAL => '1') 
    port map(
      clk      => rxusrclk2,
      rst      => cable_unpull_reset_rising_int,
      data_in  => '0',
      data_out => cable_unpull_reset_rising_rxusrclk2
    );

end wrapper;
