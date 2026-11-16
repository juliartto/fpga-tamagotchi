-------------------------------------------------------------------------------
-- tb_pet_core.vhd
-- Testbench autoverificavel das regras do jogo (pet_core).
-- CLK_HZ e reduzido para TICK_CLKS: assim cada tick de jogo dura poucos
-- ciclos de clock e a simulacao fica rapida.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.pet_pkg.all;

entity tb_pet_core is
end entity tb_pet_core;

architecture sim of tb_pet_core is
  constant CLK_PERIOD : time     := 20 ns;
  constant TICK_CLKS  : positive := 4;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal tick      : std_logic;
  signal btn_feed  : std_logic := '0';
  signal btn_play  : std_logic := '0';
  signal btn_sleep : std_logic := '0';
  signal btn_med   : std_logic := '0';
  signal state     : pet_state_t;
  signal mood      : pet_mood_t;
  signal stats     : stat_array_t;
  signal age       : age_t;
  signal stage     : pet_stage_t;
  signal alert     : std_logic;
  signal done      : boolean := false;
begin

  clk <= not clk after CLK_PERIOD / 2 when not done else '0';

  dut : entity work.pet_core
    generic map (
      CLK_HZ => TICK_CLKS)
    port map (
      clk       => clk,
      rst       => rst,
      pause     => '0',
      speed     => "00",
      btn_feed  => btn_feed,
      btn_play  => btn_play,
      btn_sleep => btn_sleep,
      btn_med   => btn_med,
      state     => state,
      mood      => mood,
      stats     => stats,
      age       => age,
      stage     => stage,
      alert     => alert,
      tick_out  => tick);

  stimulus : process
    -- pulso de um ciclo, como o gerado pelo debounce
    procedure press (signal b : out std_logic) is
    begin
      wait until rising_edge(clk);
      b <= '1';
      wait until rising_edge(clk);
      b <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure wait_clks (n : positive) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure check (cond : boolean; msg : string) is
    begin
      assert cond report "FALHA: " & msg severity error;
    end procedure;

    variable before : stat_t;
  begin
    wait_clks(3);
    rst <= '0';
    wait_clks(2);
    check(state = ST_OVO, "deveria comecar como ovo");

    -- o tempo nao passa para o ovo
    wait_clks(100);
    check(state = ST_OVO and stats(IDX_FOOD) = 10, "ovo nao deveria perder atributos");

    -- chocar
    press(btn_feed);
    check(state = ST_NORMAL, "qualquer botao deveria chocar o ovo");
    check(stats(IDX_HEALTH) = STAT_MAX, "deveria nascer com saude cheia");
    check(stage = FASE_FILHOTE, "deveria nascer como filhote");

    -- alimentar
    before := stats(IDX_FOOD);
    press(btn_feed);
    check(state = ST_COMENDO, "deveria estar comendo");
    check(stats(IDX_FOOD) > before, "alimentar deveria aumentar a saciedade");
    wait until state = ST_NORMAL for 100 * CLK_PERIOD;
    check(state = ST_NORMAL, "deveria voltar ao normal depois de comer");

    -- brincar
    before := stats(IDX_HAPPY);
    press(btn_play);
    check(state = ST_BRINCANDO, "deveria estar brincando");
    check(stats(IDX_HAPPY) > before, "brincar deveria aumentar a alegria");
    wait until state = ST_NORMAL for 100 * CLK_PERIOD;

    -- dormir recupera energia e acorda sozinho
    press(btn_sleep);
    check(state = ST_DORMINDO, "deveria estar dormindo");
    press(btn_feed);
    check(state = ST_DORMINDO, "nao deveria comer dormindo");
    wait until state /= ST_DORMINDO for 1000 * CLK_PERIOD;
    check(state = ST_NORMAL, "deveria acordar com a energia cheia");
    check(stats(IDX_ENERGY) = STAT_MAX, "energia deveria estar cheia ao acordar");

    -- sem cuidados: fica em alerta e depois morre
    if alert /= '1' then
      wait until alert = '1' for 2000 * CLK_PERIOD;
    end if;
    check(alert = '1', "deveria alertar com atributo baixo");
    wait until state = ST_MORTO for 5000 * CLK_PERIOD;
    check(state = ST_MORTO, "deveria morrer sem cuidados");
    check(stats(IDX_HEALTH) = 0, "saude deveria ser zero ao morrer");

    -- recomecar
    press(btn_med);
    check(state = ST_OVO, "botao deveria recomecar apos a morte");
    press(btn_med);
    check(state = ST_NORMAL and stats(IDX_HEALTH) = STAT_MAX,
          "novo bichinho deveria nascer saudavel");

    -- reset no meio do jogo
    rst <= '1';
    wait_clks(2);
    rst <= '0';
    wait_clks(2);
    check(state = ST_OVO, "reset deveria voltar ao ovo");

    report "tb_pet_core: fim da simulacao" severity note;
    done <= true;
    wait;
  end process;

end architecture sim;
