---------------------------------------------------------------------
-- TITLE: M-lite CPU core
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 2/15/01
-- FILENAME: mlite_cpu.vhd
-- PROJECT: M-lite CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- NOTE:  MIPS(tm) and MIPS I(tm) are registered trademarks of MIPS 
--    Technologies.  MIPS Technologies does not endorse and is not 
--    associated with this project.
-- DESCRIPTION:
-- Top level VHDL document that ties the eight other entities together.
-- Executes MIPS(tm) opcodes.  Based on information found in:
--    "MIPS RISC Architecture" by Gerry Kane and Joe Heinrich
--    and "The Designer's Guide to VHDL" by Peter J. Ashenden
-- An add instruction would take the following steps (see cpu.gif):
--    1.  The "pc_next" entity would have previously passed the program
--        counter (PC) to the "mem_ctrl" entity.
--    2.  "Mem_ctrl" passes the opcode to the "control" entity.
--    3.  "Control" converts the 32-bit opcode to a 60-bit VLWI opcode
--        and sends control signals to the other entities.
--    4.  Based on the rs_index and rt_index control signals, "reg_bank" 
--        sends the 32-bit reg_source and reg_target to "bus_mux".
--    5.  Based on the a_source and b_source control signals, "bus_mux"
--        multiplexes reg_source onto a_bus and reg_target onto b_bus.
--    6.  Based on the alu_func control signals, "alu" adds the values
--        from a_bus and b_bus and places the result on c_bus.
--    7.  Based on the c_source control signals, "bus_bux" multiplexes
--        c_bus onto reg_dest.
--    8.  Based on the rd_index control signal, "reg_bank" saves
--        reg_dest into the correct register.
-- The CPU is implemented as a two stage pipeline with step #1 in the
-- first stage and steps #2-8 occuring the second stage.
--
-- Writing to memory takes four cycles to meet RAM address hold times.
-- Addresses with a(31)='1' take two cycles (assumed to be clocked).
-- Here are the signals for writing a character to address 0xffff:
--
--      mem_write                           
--    interrupt                     mem_byte_sel
--      reset                        mem_pause  
--       ns    mem_address m_data_w m_data_r    
--   ===========================================
--     6700 0 0 0 000002A4 ZZZZZZZZ A0AE0000 0 0  (  fetch write opcode)
--     6800 0 0 0 000002B0 ZZZZZZZZ 0443FFF6 0 0  (1 fetch NEXT opcode)
--     6900 0 0 1 0000FFFF 31313131 ZZZZZZZZ 0 0  (2 address hold)
--     7000 0 0 1 0000FFFF 31313131 ZZZZZZZZ 0 1  (3 write the low byte)
--     7100 0 0 1 0000FFFF 31313131 ZZZZZZZZ 0 0  (4 address hold)
--     7200 0 0 0 000002B4 ZZZZZZZZ 00441806 0 0  (  execute NEXT opcode)
--
-- The CPU core was synthesized for 0.13 um line widths with an area
-- of 0.2 millimeters squared.  The maximum latency was less than 6 ns 
-- for a maximum clock speed of 150 MHz.
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack.all;

entity mlite_cpu is
   port(clk         : in std_logic;
        reset_in    : in std_logic;
        intr_in     : in std_logic;

        mem_address : out std_logic_vector(31 downto 0);
        mem_data_w  : out std_logic_vector(31 downto 0);
        mem_data_r  : in std_logic_vector(31 downto 0);
        mem_byte_sel: out std_logic_vector(3 downto 0); 
        mem_write   : out std_logic;
        mem_pause   : in std_logic);
end; --entity mlite_cpu

architecture logic of mlite_cpu is

component pc_next
   port(clk          : in std_logic;
        reset_in     : in std_logic;
        pc_new       : in std_logic_vector(31 downto 2);
        take_branch  : in std_logic;
        pause_in     : in std_logic;
        opcode25_0   : in std_logic_vector(25 downto 0);
        pc_source    : in pc_source_type;
        pc_out       : out std_logic_vector(31 downto 0);
        pc_out_plus4 : out std_logic_vector(31 downto 0));
end component;

component mem_ctrl
   port(clk          : in std_logic;
        reset_in     : in std_logic;
        pause_in     : in std_logic;
        nullify_op   : in std_logic;
        address_pc   : in std_logic_vector(31 downto 0);
        opcode_out   : out std_logic_vector(31 downto 0);

        address_data : in std_logic_vector(31 downto 0);
        mem_source   : in mem_source_type;
        data_write   : in std_logic_vector(31 downto 0);
        data_read    : out std_logic_vector(31 downto 0);
        pause_out    : out std_logic;
        
        mem_address  : out std_logic_vector(31 downto 0);
        mem_data_w   : out std_logic_vector(31 downto 0);
        mem_data_r   : in std_logic_vector(31 downto 0);
        mem_byte_sel : out std_logic_vector(3 downto 0);
        mem_write    : out std_logic;
        mem_pause    : in std_logic);
end component;

component control 
   port(opcode       : in  std_logic_vector(31 downto 0);
        intr_signal  : in  std_logic;
        pause_in     : in  std_logic;
        rs_index     : out std_logic_vector(5 downto 0);
        rt_index     : out std_logic_vector(5 downto 0);
        rd_index     : out std_logic_vector(5 downto 0);
        imm_out      : out std_logic_vector(15 downto 0);
        alu_func     : out alu_function_type;
        shift_func   : out shift_function_type;
        mult_func    : out mult_function_type;
        branch_func  : out branch_function_type;
        a_source_out : out a_source_type;
        b_source_out : out b_source_type;
        c_source_out : out c_source_type;
        pc_source_out: out pc_source_type;
        mem_source_out:out mem_source_type);
end component;

component reg_bank
   port(clk            : in  std_logic;
        reset_in       : in  std_logic;
        rs_index       : in  std_logic_vector(5 downto 0);
        rt_index       : in  std_logic_vector(5 downto 0);
        rd_index       : in  std_logic_vector(5 downto 0);
        reg_source_out : out std_logic_vector(31 downto 0);
        reg_target_out : out std_logic_vector(31 downto 0);
        reg_dest_new   : in  std_logic_vector(31 downto 0);
        intr_enable    : out std_logic);
end component;

component bus_mux 
   port(imm_in       : in  std_logic_vector(15 downto 0);
        reg_source   : in  std_logic_vector(31 downto 0);
        a_mux        : in  a_source_type;
        a_out        : out std_logic_vector(31 downto 0);

        reg_target   : in  std_logic_vector(31 downto 0);
        b_mux        : in  b_source_type;
        b_out        : out std_logic_vector(31 downto 0);

        c_bus        : in  std_logic_vector(31 downto 0);
        c_memory     : in  std_logic_vector(31 downto 0);
        c_pc         : in  std_logic_vector(31 downto 0);
        c_pc_plus4   : in  std_logic_vector(31 downto 0);
        c_mux        : in  c_source_type;
        reg_dest_out : out std_logic_vector(31 downto 0);

        branch_func  : in  branch_function_type;
        take_branch  : out std_logic);
end component;

component alu
   port(a_in         : in  std_logic_vector(31 downto 0);
        b_in         : in  std_logic_vector(31 downto 0);
        alu_function : in  alu_function_type;
        c_alu        : out std_logic_vector(31 downto 0));
end component;

component shifter
   port(value        : in  std_logic_vector(31 downto 0);
        shift_amount : in  std_logic_vector(4 downto 0);
        shift_func   : in  shift_function_type;
        c_shift      : out std_logic_vector(31 downto 0));
end component;

component mult
   port(clk       : in std_logic;
        a, b      : in std_logic_vector(31 downto 0);
        mult_func : in mult_function_type;
        c_mult    : out std_logic_vector(31 downto 0);
        pause_out : out std_logic);
end component;

   signal opcode         : std_logic_vector(31 downto 0);
   signal rs_index, rt_index, rd_index     : std_logic_vector(5 downto 0);
   signal reg_source, reg_target, reg_dest : std_logic_vector(31 downto 0);
   signal a_bus, b_bus, c_bus : std_logic_vector(31 downto 0);
   signal c_alu, c_shift, c_mult, c_memory
        : std_logic_vector(31 downto 0);
   signal imm            : std_logic_vector(15 downto 0);
   signal pc             : std_logic_vector(31 downto 0);
   signal pc_plus4       : std_logic_vector(31 downto 0);
   signal alu_function   : alu_function_type;
   signal shift_function : shift_function_type;
   signal mult_function  : mult_function_type;
   signal branch_function: branch_function_type;
   signal take_branch    : std_logic;
   signal a_source       : a_source_type;
   signal b_source       : b_source_type;
   signal c_source       : c_source_type;
   signal pc_source      : pc_source_type;
   signal mem_source     : mem_source_type;
   signal pause_mult     : std_logic;
   signal pause_memory   : std_logic;
   signal pause          : std_logic;
   signal nullify_op     : std_logic;
   signal intr_enable    : std_logic;
   signal intr_signal    : std_logic;
   signal reset_reg      : std_logic;
begin  --architecture

   pause <= pause_mult or pause_memory;
   nullify_op <= '1' when pc_source = from_lbranch and 
                     (take_branch = '0' or branch_function = branch_yes) else
                 '0';
   c_bus <= c_alu or c_shift or c_mult;

--synchronize reset and interrupt pins
intr_proc: process(clk, reset_in, intr_in, intr_enable, pc_source, pc, pause)
begin
   if rising_edge(clk) then
      reset_reg <= reset_in;
      --don't try to interrupt a multi-cycle instruction
      if intr_in = '1' and intr_enable = '1' and 
            pc_source = from_inc4 and 
            pc(2) = '0' and
            pause = '0' then
         --the epc will be backed up one opcode (pc-4)
         intr_signal <= '1';
      else
         intr_signal <= '0';
      end if;
   end if;
end process;

   u1_pc_next: pc_next PORT MAP (
        clk          => clk,
        reset_in     => reset_reg,
        take_branch  => take_branch,
        pause_in     => pause,
        pc_new       => c_alu(31 downto 2),
        opcode25_0   => opcode(25 downto 0),
        pc_source    => pc_source,
        pc_out       => pc,
        pc_out_plus4 => pc_plus4);

   u2_mem_ctrl: mem_ctrl PORT MAP (
        clk          => clk,
        reset_in     => reset_reg,
        pause_in     => pause,
        nullify_op   => nullify_op,
        address_pc   => pc,
        opcode_out   => opcode,

        address_data => c_alu,
        mem_source   => mem_source,
        data_write   => reg_target,
        data_read    => c_memory,
        pause_out    => pause_memory,
        
        mem_address  => mem_address,
        mem_data_w   => mem_data_w,
        mem_data_r   => mem_data_r,
        mem_byte_sel => mem_byte_sel,
        mem_write    => mem_write,
        mem_pause    => mem_pause);

   u3_control: control PORT MAP (
        opcode       => opcode,
        intr_signal  => intr_signal,
        pause_in     => pause,
        rs_index     => rs_index,
        rt_index     => rt_index,
        rd_index     => rd_index,
        imm_out      => imm,
        alu_func     => alu_function,
        shift_func   => shift_function,
        mult_func    => mult_function,
        branch_func  => branch_function,
        a_source_out => a_source,
        b_source_out => b_source,
        c_source_out => c_source,
        pc_source_out=> pc_source,
        mem_source_out=> mem_source);

   u4_reg_bank: reg_bank port map (
        clk            => clk,
        reset_in       => reset_reg,
        rs_index       => rs_index,
        rt_index       => rt_index,
        rd_index       => rd_index,
        reg_source_out => reg_source,
        reg_target_out => reg_target,
        reg_dest_new   => reg_dest,
        intr_enable    => intr_enable);

   u5_bus_mux: bus_mux port map (
        imm_in       => imm,
        reg_source   => reg_source,
        a_mux        => a_source,
        a_out        => a_bus,

        reg_target   => reg_target,
        b_mux        => b_source,
        b_out        => b_bus,

        c_bus        => c_bus,
        c_memory     => c_memory,
        c_pc         => pc,
        c_pc_plus4   => pc_plus4,
        c_mux        => c_source,
        reg_dest_out => reg_dest,

        branch_func  => branch_function,
        take_branch  => take_branch);

   u6_alu: alu port map (
        a_in         => a_bus,
        b_in         => b_bus,
        alu_function => alu_function,
        c_alu        => c_alu);

   u7_shifter: shifter port map (
        value        => b_bus,
        shift_amount => a_bus(4 downto 0),
        shift_func   => shift_function,
        c_shift      => c_shift);

   u8_mult: mult port map (
        clk       => clk,
        a         => a_bus,
        b         => b_bus,
        mult_func => mult_function,
        c_mult    => c_mult,
        pause_out => pause_mult);

end; --architecture logic

