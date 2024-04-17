--+----------------------------------------------------------------------------
--| 
--| COPYRIGHT 2018 United States Air Force Academy All rights reserved.
--| 
--| United States Air Force Academy     __  _______ ___    _________ 
--| Dept of Electrical &               / / / / ___//   |  / ____/   |
--| Computer Engineering              / / / /\__ \/ /| | / /_  / /| |
--| 2354 Fairchild Drive Ste 2F6     / /_/ /___/ / ___ |/ __/ / ___ |
--| USAF Academy, CO 80840           \____//____/_/  |_/_/   /_/  |_|
--| 
--| ---------------------------------------------------------------------------
--|
--| FILENAME      : top_basys3.vhd
--| AUTHOR(S)     : Capt Phillip Warner, C3C Jack West
--| CREATED       : 3/9/2018  MOdified by Capt Dan Johnson (3/30/2020) C3C Jack West (4/9/2024)
--| DESCRIPTION   : This file implements the top level module for a BASYS 3 to 
--|					drive the Lab 4 Design Project (Advanced Elevator Controller).
--|
--|					Inputs: clk       --> 100 MHz clock from FPGA
--|							btnL      --> Rst Clk
--|							btnR      --> Rst FSM
--|							btnU      --> Rst Master
--|							btnC      --> GO (request floor)
--|							sw(15:12) --> Passenger location (floor select bits)
--| 						sw(3:0)   --> Desired location (floor select bits)
--| 						 - Minumum FUNCTIONALITY ONLY: sw(1) --> up_down, sw(0) --> stop
--|							 
--|					Outputs: led --> indicates elevator movement with sweeping pattern (additional functionality)
--|							   - led(10) --> led(15) = MOVING UP
--|							   - led(5)  --> led(0)  = MOVING DOWN
--|							   - ALL OFF		     = NOT MOVING
--|							 an(3:0)    --> seven-segment display anode active-low enable (AN3 ... AN0)
--|							 seg(6:0)	--> seven-segment display cathodes (CG ... CA.  DP unused)
--|
--| DOCUMENTATION : None
--|
--+----------------------------------------------------------------------------
--|
--| REQUIRED FILES :
--|
--|    Libraries : ieee
--|    Packages  : std_logic_1164, numeric_std
--|    Files     : MooreElevatorController.vhd, clock_divider.vhd, sevenSegDecoder.vhd
--|				   thunderbird_fsm.vhd, sevenSegDecoder, TDM4.vhd, OTHERS???
--|
--+----------------------------------------------------------------------------
--|
--| NAMING CONVENSIONS :
--|
--|    xb_<port name>           = off-chip bidirectional port ( _pads file )
--|    xi_<port name>           = off-chip input port         ( _pads file )
--|    xo_<port name>           = off-chip output port        ( _pads file )
--|    b_<port name>            = on-chip bidirectional port
--|    i_<port name>            = on-chip input port
--|    o_<port name>            = on-chip output port
--|    c_<signal name>          = combinatorial signal
--|    f_<signal name>          = synchronous signal
--|    ff_<signal name>         = pipeline stage (ff_, fff_, etc.)
--|    <signal name>_n          = active low signal
--|    w_<signal name>          = top level wiring signal
--|    g_<generic name>         = generic
--|    k_<constant name>        = constant
--|    v_<variable name>        = variable
--|    sm_<state machine type>  = state machine type definition
--|    s_<signal name>          = state name
--|
--+----------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;


-- Lab 4
entity top_basys3 is
    port(
        -- inputs
        clk     :   in std_logic; -- native 100MHz FPGA clock
        sw      :   in std_logic_vector(15 downto 0);
        btnU    :   in std_logic; -- master_reset
        btnL    :   in std_logic; -- clk_reset
        btnR    :   in std_logic; -- fsm_reset
        
        -- outputs
        led :   out std_logic_vector(15 downto 0);
        -- 7-segment display segments (active-low cathodes)
        seg :   out std_logic_vector(6 downto 0);
        -- 7-segment display active-low enables (anodes)
        an  :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
	-- declare components and signals
	
	-- From ICE 5
	component elevator_controller_fsm is
	   port (
	       i_clk     : in  STD_LOGIC;
           i_reset   : in  STD_LOGIC;
           i_stop    : in  STD_LOGIC;
           i_up_down : in  STD_LOGIC;
           o_floor   : out STD_LOGIC_VECTOR (3 downto 0)
	   );
	end component elevator_controller_fsm;
	
	-- From Lab 2
	component sevenSegDecoder is
	   port (
	       i_D : in std_logic_vector(3 downto 0);
           o_S : out std_logic_vector(6 downto 0)
	   );
	end component sevenSegDecoder;
	
	-- From clock_divider file already present in this lab
	component clock_divider is
	   generic ( constant k_DIV : natural := 2	); -- How many clk cycles until slow clock toggles
                                                   -- Effectively, you divide the clk double this 
                                                   -- number (e.g., k_DIV := 2 --> clock divider of 4)
        port (  i_clk    : in std_logic;
                i_reset  : in std_logic;           -- asynchronous
                o_clk    : out std_logic           -- divided (slow) clock
        );
	end component clock_divider;
	

	
	component TDM4 is
	   generic ( constant k_WIDTH : natural  := 4); -- k_WIDTH changed from 4 (two signals to send?)
	   port (
	       i_clk		: in  STD_LOGIC;
           i_reset        : in  STD_LOGIC; -- asynchronous
           i_D3         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
           i_D2         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
           i_D1         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
           i_D0         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
           o_data        : out STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
           o_sel        : out STD_LOGIC_VECTOR (3 downto 0)    -- selected data line (one-cold)
	   
	   );
	end component TDM4;
	
	--Signals
    signal w_clk : std_logic;
    signal w_clk2 : std_logic;
    signal w_D : std_logic_vector(3 downto 0); -- wires that connect floor output of fsm to inputs of decoder
    signal w_left : std_logic_vector(3 downto 0); --left anode (10's place)
    signal w_right : std_logic_vector(3 downto 0); -- right anode (1's place)
    signal w_sevenSeg : std_logic_vector(3 downto 0); 
  
begin
	-- PORT MAPS ----------------------------------------
    elevator_controller_fsm_inst : elevator_controller_fsm
    port map (
        i_clk => w_clk,
        i_reset => btnR, 
        i_stop => sw(0),
        i_up_down => sw(1),
       
        
       o_floor(0) => w_D(0),
       o_floor(1) => w_D(1),
       o_floor(2) => w_D(2),
       o_floor(3) => w_D(3)
    );
    
    sevenSegDecoder_inst : sevenSegDecoder
    port map (
        i_D => w_sevenSeg,
        
        
        o_S(0) => seg(0),
        o_S(1) => seg(1),
        o_S(2) => seg(2),
        o_S(3) => seg(3),
        o_S(4) => seg(4),
        o_S(5) => seg(5),
        o_S(6) => seg(6)
    
    );
    
	clk_div_inst : clock_divider
	generic map (k_DIV => 25000000) -- change this k_DIV? 12500000 = 4 Hz 
	port map (
	   i_clk => clk,
	   i_reset => btnL,
	   o_clk => w_clk
	);
	
	-- Help with implementation from C3C Wu
	clk_div_inst2 : clock_divider                                                                        
	generic map (k_DIV => 1000)
	port map (
	   i_clk => clk,
	   i_reset => btnL,
	   o_clk => w_clk2
	);
	
	TDM4_inst : TDM4
	port map (
	   i_clk => w_clk2,
	   i_reset => btnU,
	   i_D0 => "0000", -- Help from C3C Wu
	   i_D1 => "0000", -- Help from C3C Wu
	   i_D2 => w_right,-- right anode
	   i_D3 => w_left, -- left anode	
	   o_sel => an, -- Help from C3C Wu
	   o_data =>  w_sevenSeg     
	);
	
	-- CONCURRENT STATEMENTS ----------------------------
	-- w_left and w_right statements created with help from C3C Brenden Wu
	w_left <= "0001" when w_D = "1010" or
	 w_D = "1011" or 
	 w_D = "1100" or 
	 w_D = "1101" or 
	 w_D = "1110" or 
	 w_D = "1111" or
	 w_D = "0000" else
	"0000";
	
	w_right <= "0001" when (w_D = "0001" or w_D = "1011") else 
	"0000" when w_D = "1010" else --10
	"0010" when (w_D = "0010" or w_D = "1100")  else 
	"0011" when (w_D = "0011" or w_D = "1101") else 
	"0100" when (w_D = "0100" or w_D = "1110") else 
	"0101" when (w_D = "0101" or w_D = "1111") else 
	"0110" when (w_D = "0110" or w_D = "0000") else 
	"0111" when w_D = "0111" else 
	"1000" when w_D = "1000" else 
	"1001" when w_D = "1001"; 
	
	
	-- LED 15 gets the FSM slow clock signal. The rest are grounded.
	led(15) <= w_clk;
	led(14) <= '0';
	
	
	-- leave unused switches UNCONNECTED. Ignore any warnings this causes.
	
	-- wire up active-low 7SD anodes (an) as required
	an(0) <= '1';
	an(1) <= '1';
	-- Tie any unused anodes to power ('1') to keep them off
	
end top_basys3_arch;
