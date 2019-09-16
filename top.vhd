--
-- FPGA design for a simple LED panel based EXTA implementation
-- Created on 2018/07/25 by A. Schweizer
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
port (
  -- Input signals
  i_clk: in std_logic;
  i_pushbutton: in std_logic;
  i_1pps: in std_logic;
  -- Output signals for the LED display
  o_r1: out std_logic; -- lower half of the display
  o_g1: out std_logic;
  o_b1: out std_logic;
  o_r2: out std_logic; -- upper half of the display
  o_g2: out std_logic;
  o_b2: out std_logic;
  o_a: out std_logic; -- address
  o_b: out std_logic;
  o_c: out std_logic;
  o_d: out std_logic;
  o_clk: out std_logic; -- display clock
  o_stb: out std_logic; -- display strobe signal
  o_oe: out std_logic -- display output enable
);
end top;

architecture Behavioral of top is

signal s_pushbutton: std_logic;
signal s_debounce_ctr: unsigned(23 downto 0);
signal s_debounce_input: std_logic_vector(5 downto 0) := "000000";

signal s_1pps_d: std_logic;
signal s_1pps: std_logic;

signal s_speed_level: unsigned(6 downto 0) := "0000001"; -- 1/1 to 1/16 second
signal s_speed_threshold: unsigned(19 downto 0) := "00001000000011100111"; -- 0x80e7

signal s: std_logic;

signal s_r1: std_logic;
signal s_g1: std_logic;
signal s_b1: std_logic;
signal s_r2: std_logic;
signal s_g2: std_logic;
signal s_b2: std_logic;
signal s_a: std_logic;
signal s_b: std_logic;
signal s_c: std_logic;
signal s_d: std_logic;
signal s_clk: std_logic;
signal s_stb: std_logic;
signal s_oe: std_logic;

type t_state is (IDLE, CLK_HI, CLK_LO, STB_HI, STB_LO, NEXT_ADDR);
signal s_state: t_state;
signal s_addr_ctr: unsigned(3 downto 0);
signal s_addr: unsigned(3 downto 0);
signal s_bit_ix: unsigned(6 downto 0);

signal s_slow_ctr: unsigned(19 downto 0);
signal s_border_pwm_ctr: unsigned(5 downto 0);

signal s_second_ctr: unsigned(25 downto 0) := (others => '0');
signal s_second_mark: unsigned(6 downto 0) := "0111001";

signal s_x: unsigned(5 downto 0) := "111000"; -- 56...7
signal s_y: unsigned(4 downto 0) := "01001"; -- 19...0
signal s_top: std_logic := '1';

signal s_pos_match: std_logic;
signal s_speed_indicator: std_logic;
signal s_second_indicator: std_logic;
signal s_top_border: std_logic;
signal s_bottom_border: std_logic;

begin

-- (pin numbers correspond to the XC2V40 test board, see UCF)

o_r1 <= s_r1; -- D11
o_g1 <= s_g1; -- D13
o_b1 <= s_b1; -- E11
o_r2 <= s_r2; -- C13
o_g2 <= s_g2; -- G10
o_b2 <= s_b2; -- G13

o_a <= s_a; -- G12
o_b <= s_b; -- H12
o_c <= s_c; -- H11
o_d <= s_d; -- J13
o_clk <= s_clk; -- J10
o_stb <= s_stb; -- K13
o_oe <= s_oe; -- K12

s_a <= s_addr(0);
s_b <= s_addr(1);
s_c <= s_addr(2);
s_d <= s_addr(3);


-- by clicking on the push button, the user can change the speed of the moving LED
s_speed_threshold <= x"080e7" when s_speed_level = 1
                else x"04073" when s_speed_level = 2
                else x"02039" when s_speed_level = 4
                else x"0101c" when s_speed_level = 8
                else x"0080d";

s_speed_indicator <= '1' 
  when (s_addr_ctr = 12 and s_bit_ix >= 57 - s_speed_level and s_bit_ix < 57) 
  else '0';

s_second_indicator <= '1'
  when (s_addr_ctr = 3 and s_bit_ix = s_second_mark)
  else '0';


s_top_border <= '1' when ((s_bit_ix = 6 or s_bit_ix = 57) and s_addr_ctr < 11) 
                      or (s_addr_ctr = 10 and s_bit_ix > 5 and s_bit_ix < 58) else '0';

s_bottom_border <= '1' when ((s_bit_ix = 6 or s_bit_ix = 57) and s_addr_ctr > 5) 
                      or (s_addr_ctr = 5 and s_bit_ix > 5 and s_bit_ix < 58) else '0';


s_pos_match <= '1' when s_bit_ix = s_x and s_y = s_addr_ctr else '0';

-- upper half of the display
s_r2 <= '1' when (s_border_pwm_ctr = "000000" and s_top_border = '1') 
              or (s_top = '1' and s_pos_match = '1') else '0';
s_g2 <= '1' when s_top = '1' and s_pos_match = '1' else '0';
s_b2 <= '1' when (s_border_pwm_ctr = "000000" and s_speed_indicator = '1')
              or (s_top = '1' and s_pos_match = '1') else '0';

-- lower half of the display
s_r1 <= '1' when (s_border_pwm_ctr = "000000" and s_bottom_border = '1') 
              or (s_top = '0' and s_pos_match = '1') else '0';
s_g1 <= '1' when (s_border_pwm_ctr = "000000" and s_second_indicator = '1')
              or (s_top = '0' and s_pos_match = '1') else '0';
s_b1 <= '1' when s_top = '0' and s_pos_match = '1' else '0';


process (i_clk)
begin
  if rising_edge(i_clk) then

    -- synchronize the input signals
    s_pushbutton <= i_pushbutton;
    s_1pps_d <= i_1pps;
    s_1pps <= s_1pps_d;
  
    if s = '1' then
      s <= '0';
    else
      s <= '1';
    end if;

    -- debounce the push button, change the speed level on button press
    if s_debounce_ctr = 6000 then
      s_debounce_ctr <= (others => '0');
      s_debounce_input(5 downto 1) <= s_debounce_input(4 downto 0);
      s_debounce_input(0) <= s_pushbutton;
      if s_debounce_input = "000111" then -- key released
        if s_speed_level = "0010000" 
           or s_speed_level = "0001000" 
           or s_speed_level = "0000100" then
          s_speed_level <= "0000001";
        else
          s_speed_level <= s_speed_level(5 downto 0) & "0";
        end if;
      end if;
    else
      s_debounce_ctr <= s_debounce_ctr + 1;
    end if;

    -- if 1ms has elapsed, we activate the next LED in the array;
    -- if a 1pps pulse has been received, we activate the top-left LED;
    -- we use lines 9 to 0 in the top half and lines 15 to 6 in the bottom half;
    -- we use columns 56 (left border) to 7 (right border) for the EXTA array;

    if s_1pps = '0' and s_1pps_d = '1' then
      -- 1pps signal received, activate LED at coordinate 1/1
      s_slow_ctr <= (others => '0');
      s_x <= "111000"; -- back to left side
      s_y <= "01001"; -- 9 to 0
      s_top <= '1';

    elsif s_slow_ctr = s_speed_threshold then --32999 then -- 33 MHz to 1 kHz
      s_slow_ctr <= (others => '0');

      -- one millisecond has elapsed, activate the next LED

      if s_x = 7 then
        -- right border reached
        s_x <= "111000"; -- back to left border; 56 down to 7
        -- one line down
        if s_top = '0' then -- bottom, s_y from 6 to 15
          if s_y = 6 then
            s_top <= '1';
            s_y <= "01001"; -- top: 9 to 0
          else
            s_y <= s_y - 1;
          end if;
        else -- s_top = '1'
          if s_y = 0 then
            s_top <= '0';
            s_y <= "01111"; -- bottom: 15 to 6
          else
            s_y <= s_y - 1;
          end if;
        end if;
      else
        s_x <= s_x - 1;
      end if;

      -- a separate, single LED indicates the second and moves by 1 position every 1000 ms
	
      if s_second_ctr = 999 then
        s_second_ctr <= (others => '0');
        if s_second_mark = 6 then
          s_second_mark <= "0111001";
        else
          s_second_mark <= s_second_mark - 1;
        end if;
      else
        s_second_ctr <= s_second_ctr + 1;
      end if;

    else
      s_slow_ctr <= s_slow_ctr + 1;
    end if;

    -- state machine for the LED panel control signals

    case s_state is
      -- start with everything 'low'
      when IDLE =>
        s_oe <= '0';
        s_clk <= '0';
        s_stb <= '0';
        s_state <= CLK_HI;

      -- clock in 64 bits
      when CLK_HI =>
        s_clk <= '1';
        s_state <= CLK_LO;
      when CLK_LO =>
        s_clk <= '0';
        if s_bit_ix = "111111" then
          s_state <= STB_HI;
        else 
          s_state <= CLK_HI;
        end if;
        s_bit_ix <= s_bit_ix + 1;
		
      -- disable the leds, load shift registers, increase row
      when STB_HI =>
        s_oe <= '1';
        s_stb <= '1'; -- load shift registers into LED
        s_state <= STB_LO;
      when STB_LO =>
        s_stb <= '0'; -- load complete
        s_state <= NEXT_ADDR;
      when NEXT_ADDR =>
        s_addr <= s_addr_ctr;
        if s_addr_ctr = 15 then
          s_addr_ctr <= (others => '0');
          s_border_pwm_ctr <= s_border_pwm_ctr + 1;
        else
          s_addr_ctr <= s_addr_ctr + 1; -- next address
        end if;
        s_state <= IDLE;

      when others =>
        s_state <= IDLE;
    end case;
	 
  end if;
end process;

end Behavioral;

