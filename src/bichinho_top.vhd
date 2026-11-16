-------------------------------------------------------------------------------
-- bichinho_top.vhd
-- Bichinho virtual na DE2-115. Este arquivo tem duas entidades:
--
--   debounce      filtra um botao e gera um pulso por pressionamento
--   bichinho_top  top-level: liga os botoes, o jogo, o LCD, os displays de
--                 7 segmentos e os LEDs
--
--   KEY3 alimentar | KEY2 brincar | KEY1 dormir/acordar | KEY0 remedio
--   SW17 reset     | SW0 pausa    | SW2..SW1 velocidade do tempo (1x a 8x)
--   SW3 tela do LCD: para baixo, o bichinho; para cima, os atributos
--   HEX7..6 idade  | HEX3..0 saciedade, alegria, energia, saude
--   LEDR piscam quando algum atributo esta baixo | LEDG7..0 saude | LEDG8 tick
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- debounce
--
-- Sincroniza o botao com o clock e so aceita uma mudanca de nivel depois de
-- DEBOUNCE_MS sem oscilar. "pressed" dura um ciclo de clock por toque.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity debounce is
  generic (
    CLK_HZ      : positive := 50_000_000;
    DEBOUNCE_MS : positive := 10;
    ACTIVE_LOW  : boolean  := true
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    btn_in  : in  std_logic;
    pressed : out std_logic
  );
end entity debounce;

architecture rtl of debounce is
  constant COUNT_MAX : natural := (CLK_HZ / 1000) * DEBOUNCE_MS;

  signal sync   : std_logic_vector(1 downto 0) := "00";
  signal stable : std_logic                    := '0';
  signal cnt    : natural range 0 to COUNT_MAX := 0;
begin

  process (clk)
    variable raw : std_logic;
  begin
    if rising_edge(clk) then
      if ACTIVE_LOW then
        raw := not btn_in;
      else
        raw := btn_in;
      end if;
      sync    <= sync(0) & raw;
      pressed <= '0';

      if rst = '1' then
        stable <= '0';
        cnt    <= 0;
      elsif sync(1) /= stable then
        if cnt = COUNT_MAX then
          stable  <= sync(1);
          pressed <= sync(1);
          cnt     <= 0;
        else
          cnt <= cnt + 1;
        end if;
      else
        cnt <= 0;
      end if;
    end if;
  end process;

end architecture rtl;

-------------------------------------------------------------------------------
-- bichinho_top
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.pet_pkg.all;

entity bichinho_top is
  generic (
    CLK_HZ : positive := 50_000_000
  );
  port (
    CLOCK_50 : in  std_logic;
    KEY      : in  std_logic_vector(3 downto 0);
    SW       : in  std_logic_vector(17 downto 0);
    LEDR     : out std_logic_vector(17 downto 0);
    LEDG     : out std_logic_vector(8 downto 0);
    HEX0     : out std_logic_vector(6 downto 0);
    HEX1     : out std_logic_vector(6 downto 0);
    HEX2     : out std_logic_vector(6 downto 0);
    HEX3     : out std_logic_vector(6 downto 0);
    HEX4     : out std_logic_vector(6 downto 0);
    HEX5     : out std_logic_vector(6 downto 0);
    HEX6     : out std_logic_vector(6 downto 0);
    HEX7     : out std_logic_vector(6 downto 0);
    LCD_DATA : out std_logic_vector(7 downto 0);
    LCD_RS   : out std_logic;
    LCD_RW   : out std_logic;
    LCD_EN   : out std_logic;
    LCD_ON   : out std_logic;
    LCD_BLON : out std_logic
  );
end entity bichinho_top;

architecture rtl of bichinho_top is
  signal clk : std_logic;

  -- chaves sincronizadas com o clock
  signal rst_sync   : std_logic_vector(1 downto 0) := "11";
  signal rst        : std_logic;
  signal pause_sync : std_logic_vector(1 downto 0) := "00";
  signal speed_s0   : std_logic_vector(1 downto 0) := "00";
  signal speed_s1   : std_logic_vector(1 downto 0) := "00";
  signal screen_sync : std_logic_vector(1 downto 0) := "00";

  signal btn : std_logic_vector(3 downto 0);

  -- jogo
  signal tick     : std_logic;
  signal state    : pet_state_t;
  signal mood     : pet_mood_t;
  signal stats    : stat_array_t;
  signal age      : age_t;
  signal stage    : pet_stage_t;
  signal alert    : std_logic;
  signal tick_led : std_logic := '0';
begin

  clk <= CLOCK_50;

  -----------------------------------------------------------------------------
  -- Chaves (entradas assincronas)
  -----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      rst_sync   <= rst_sync(0) & SW(17);
      pause_sync <= pause_sync(0) & SW(0);
      screen_sync <= screen_sync(0) & SW(3);
      speed_s0   <= SW(2 downto 1);
      speed_s1   <= speed_s0;
    end if;
  end process;

  rst <= rst_sync(1);

  -----------------------------------------------------------------------------
  -- Botoes: um debounce por KEY
  -----------------------------------------------------------------------------
  gen_buttons : for i in KEY'range generate
    u_debounce : entity work.debounce
      generic map (
        CLK_HZ => CLK_HZ)
      port map (
        clk     => clk,
        rst     => rst,
        btn_in  => KEY(i),
        pressed => btn(i));
  end generate gen_buttons;

  -----------------------------------------------------------------------------
  -- Jogo
  -----------------------------------------------------------------------------
  u_core : entity work.pet_core
    generic map (
      CLK_HZ => CLK_HZ)
    port map (
      clk       => clk,
      rst       => rst,
      pause     => pause_sync(1),
      speed     => speed_s1,
      btn_feed  => btn(3),
      btn_play  => btn(2),
      btn_sleep => btn(1),
      btn_med   => btn(0),
      state     => state,
      mood      => mood,
      stats     => stats,
      age       => age,
      stage     => stage,
      alert     => alert,
      tick_out  => tick);

  -----------------------------------------------------------------------------
  -- LCD 16x2
  -----------------------------------------------------------------------------
  u_lcd : entity work.pet_lcd
    generic map (
      CLK_HZ => CLK_HZ)
    port map (
      clk      => clk,
      screen   => screen_sync(1),
      state    => state,
      mood     => mood,
      stage    => stage,
      stats    => stats,
      age      => age,
      lcd_data => LCD_DATA,
      lcd_rs   => LCD_RS,
      lcd_rw   => LCD_RW,
      lcd_en   => LCD_EN);

  LCD_ON   <= '1';
  LCD_BLON <= '1';

  -----------------------------------------------------------------------------
  -- Displays de 7 segmentos
  -----------------------------------------------------------------------------
  HEX7 <= to_seg7(age / 10);
  HEX6 <= to_seg7(age mod 10);
  HEX5 <= SEG7_OFF;
  HEX4 <= SEG7_OFF;
  HEX3 <= to_seg7(stats(IDX_FOOD));
  HEX2 <= to_seg7(stats(IDX_HAPPY));
  HEX1 <= to_seg7(stats(IDX_ENERGY));
  HEX0 <= to_seg7(stats(IDX_HEALTH));

  -----------------------------------------------------------------------------
  -- LEDs
  -----------------------------------------------------------------------------
  -- tick_led inverte a cada tick de jogo
  process (clk)
  begin
    if rising_edge(clk) then
      if tick = '1' then
        tick_led <= not tick_led;
      end if;
    end if;
  end process;

  LEDG(8) <= tick_led;

  -- LEDs vermelhos piscam quando algum atributo esta baixo
  LEDR <= (others => alert and tick_led);

  -- saude como barra de LEDs verdes
  gen_health_leds : for i in 0 to 7 generate
    LEDG(i) <= '1' when stats(IDX_HEALTH) > 2 * i else '0';
  end generate gen_health_leds;

end architecture rtl;
