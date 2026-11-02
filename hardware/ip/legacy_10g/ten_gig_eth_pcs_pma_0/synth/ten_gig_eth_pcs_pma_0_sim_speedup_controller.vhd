-----------------------------------------------------------------------------
-- Title      : Simulation Speedup Controller
-- Project    : 10 Gigabit Ethernet PCS/PMA Core
-- File       : ten_gig_eth_pcs_pma_0_sim_speedup_controller.vhd
-- Author     : Xilinx Inc.
-- Description: This module provides a parameterizable simulation
--              speedup controller which requires a rising edge on 
--              the control input to set the output to the SIM_VALUE
--              parameter. Otherwise the output is fixed at the
--              SYNTH_VALUE parameter.
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

library unisim;
use unisim.vcomponents.all;

entity ten_gig_eth_pcs_pma_0_sim_speedup_controller is 
  generic
  (
    SYNTH_VALUE : std_logic_vector(23 downto 0) := x"11A4A6";
    SIM_VALUE   : std_logic_vector(23 downto 0) := x"00061B"
  );
  port 
  (
    clk : in std_logic;
    sim_speedup_control : in std_logic;
    sim_speedup_value : out std_logic_vector(23 downto 0) := SYNTH_VALUE
  );
end ten_gig_eth_pcs_pma_0_sim_speedup_controller;

architecture rtl of ten_gig_eth_pcs_pma_0_sim_speedup_controller is
  
  signal control_reg : std_logic := '1';
  signal control_reg1 : std_logic := '1';
  signal control_rising : std_logic := '0';
  signal load_sim_value_control : std_logic;
  signal load_sim_value_control_del : std_logic;
  signal load_sim_speedup_value : std_logic;
    
begin

  first_regs : process(clk)
  begin 
    if (clk'event and clk = '1') then
      control_reg <= sim_speedup_control;
      control_reg1 <= control_reg;
    end if;
  end process first_regs;
  
  rising_edge_detect : process(clk)
  begin
    if (clk'event and clk = '1') then
      control_rising <= control_reg and not(control_reg1);
    end if;
  end process rising_edge_detect;
  
  load_sim_value_control <= control_rising and sim_speedup_control;
  
  -- Add a delta delay to the D input to the Latch, to avoid a race
  simple_delay_inst : LUT1
    generic map(INIT => X"2")
    port map
      (I0 => load_sim_value_control,
        O => load_sim_value_control_del);
        
  -- Intentionally instance a Latch here (for simulation only!)
  load_sim_speedup_value_reg : LDCE 
    generic map(INIT => '0') 
    port map
     (CLR => '0',
      GE => '1',
      D => load_sim_value_control_del,
      G => load_sim_value_control,
      Q => load_sim_speedup_value
    );
   
  output_proc : process(load_sim_speedup_value)
  begin
    if(load_sim_speedup_value = '1') then
      sim_speedup_value <= SIM_VALUE;
    else
      sim_speedup_value <= SYNTH_VALUE;
    end if;
  end process output_proc;
  
end rtl;
