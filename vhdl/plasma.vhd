---------------------------------------------------------------------
-- TITLE: Plasma (CPU core with memory)
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 6/4/02
-- FILENAME: plasma.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    This entity combines the CPU core with memory and a UART.
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack.all;

entity plasma is
   generic(memory_type : string := "ALTERA";
           log_file    : string := "UNUSED");
   port(clk_in           : in std_logic;
        reset_in         : in std_logic;
        intr_in          : in std_logic;

        uart_read        : in std_logic;
        uart_write       : out std_logic;

        mem_address_out  : out std_logic_vector(31 downto 0);
        mem_data         : inout std_logic_vector(31 downto 0);
        mem_byte_sel_out : out std_logic_vector(3 downto 0); 
        mem_write_out    : out std_logic;
        mem_pause_in     : in std_logic);
end; --entity plasma

architecture logic of plasma is
   signal clk            : std_logic;
   signal mem_address    : std_logic_vector(31 downto 0);
   signal mem_byte_sel   : std_logic_vector(3 downto 0);
   signal mem_write      : std_logic;
   signal mem_pause      : std_logic;
   signal mem_pause_uart : std_logic;
   signal uart_sel       : std_logic;
begin  --architecture
   clk_control1:
   if log_file = "UNUSED" generate
      --convert 33MHz clock to 16.5MHz clock
      clk_div: process(clk_in, reset_in, clk)
      begin
         if rising_edge(clk_in) then
            if reset_in = '1' then
               clk <= '0';
            else
               clk <= not clk;
            end if;
         end if;
      end process; --clk_div
   end generate; --clk_control1

   clk_control2:
   if log_file /= "UNUSED" generate
      clk <= clk_in;
   end generate; --clk_control2 

   mem_pause <= mem_pause_in or mem_pause_uart;
   uart_sel <= '1' when mem_address(12 downto 0) = ONES(12 downto 0) and mem_byte_sel /= "0000" else
               '0';

   u1_cpu: mlite_cpu 
      generic map (memory_type => memory_type)
      PORT MAP (
         clk          => clk_in,
         reset_in     => reset_in,
         intr_in      => intr_in,
 
         mem_address  => mem_address,
         mem_data_w   => mem_data,
         mem_data_r   => mem_data,
         mem_byte_sel => mem_byte_sel,
         mem_write    => mem_write,
         mem_pause    => mem_pause);

   u2_ram: ram 
      generic map (memory_type => memory_type)
      PORT MAP (
         clk          => clk_in,
         mem_byte_sel => mem_byte_sel,
         mem_write    => mem_write,
         mem_address  => mem_address,
         mem_data     => mem_data);

   u3_uart: uart
      generic map (log_file => log_file)
      port map(
         clk        => clk_in,
         reset      => reset_in,
         uart_sel   => uart_sel,
         data       => mem_data(7 downto 0),
         uart_write => uart_write,
         uart_read  => uart_read,
         pause      => mem_pause_uart);

   mem_address_out  <= mem_address;
   mem_byte_sel_out <= mem_byte_sel;
   mem_write_out    <= mem_write;

end; --architecture logic