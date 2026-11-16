-------------------------------------------------------------------------------
-- pet_core.vhd
-- Regras do bichinho virtual: maquina de estados e atributos.
--
-- O modulo gera a sua propria base de tempo: um "tick" por segundo de jogo,
-- que pode ser acelerado (speed) ou congelado (pause). Todos os periodos sao
-- medidos em ticks. Os atributos vao de 0 a STAT_MAX; quanto maior, melhor.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.pet_pkg.all;

entity pet_core is
  generic (
    CLK_HZ        : positive := 50_000_000;
    FOOD_PERIOD   : positive := 8;   -- ticks para perder 1 de saciedade
    HAPPY_PERIOD  : positive := 10;  -- ticks para perder 1 de alegria
    ENERGY_PERIOD : positive := 12;  -- ticks para perder 1 de energia
    SLEEP_PERIOD  : positive := 2;   -- ticks para ganhar 1 de energia dormindo
    HEALTH_PERIOD : positive := 4;   -- ticks entre avaliacoes da saude
    DAY_TICKS     : positive := 60;  -- ticks por "dia" de idade
    JOVEM_AGE     : positive := 3;   -- idade (dias) em que vira jovem
    ADULTO_AGE    : positive := 6;   -- idade (dias) em que vira adulto
    ACTION_TICKS  : positive := 3;   -- duracao das animacoes de acao
    FEED_GAIN     : positive := 4;
    PLAY_GAIN     : positive := 4;
    PLAY_COST     : positive := 2;   -- energia gasta ao brincar
    MED_GAIN      : positive := 4;
    MED_COST      : positive := 2;   -- alegria perdida com o remedio
    START_LEVEL   : stat_t   := 10;  -- atributos ao nascer
    LOW_LEVEL     : stat_t   := 4    -- limite de "atributo baixo"
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    pause     : in  std_logic;
    speed     : in  std_logic_vector(1 downto 0);  -- 1x, 2x, 4x, 8x
    btn_feed  : in  std_logic;   -- pulsos de 1 ciclo
    btn_play  : in  std_logic;
    btn_sleep : in  std_logic;
    btn_med   : in  std_logic;
    state     : out pet_state_t;
    mood      : out pet_mood_t;
    stats     : out stat_array_t;
    age       : out age_t;
    stage     : out pet_stage_t; -- fase da vida, conforme a idade
    alert     : out std_logic;   -- algum atributo esta baixo
    tick_out  : out std_logic    -- pulso de 1 ciclo a cada tick de jogo
  );
end entity pet_core;

architecture rtl of pet_core is
  subtype cnt_t is natural range 0 to 1023;

  constant STATS_RESET : stat_array_t := (
    IDX_FOOD   => START_LEVEL,
    IDX_HAPPY  => START_LEVEL,
    IDX_ENERGY => START_LEVEL,
    IDX_HEALTH => STAT_MAX);

  signal st      : pet_state_t := ST_OVO;
  signal r_stats : stat_array_t := STATS_RESET;
  signal r_age   : age_t := 0;
  signal act_cnt : natural range 0 to ACTION_TICKS := 0;
  signal any_btn : std_logic;
  signal r_mood  : pet_mood_t;

  signal tick     : std_logic := '0';
  signal tick_cnt : natural range 0 to CLK_HZ - 1 := 0;
begin

  assert 2 * FOOD_PERIOD <= cnt_t'high and HAPPY_PERIOD <= cnt_t'high
     and ENERGY_PERIOD <= cnt_t'high and SLEEP_PERIOD <= cnt_t'high
     and HEALTH_PERIOD <= cnt_t'high and DAY_TICKS <= cnt_t'high
    report "pet_core: periodo maior que o contador suporta"
    severity failure;

  any_btn <= btn_feed or btn_play or btn_sleep or btn_med;

  state <= st;
  stats <= r_stats;
  age   <= r_age;
  mood  <= r_mood;

  -----------------------------------------------------------------------------
  -- Base de tempo: o contador avanca "step" por ciclo, entao a velocidade
  -- dobra a cada incremento de speed
  -----------------------------------------------------------------------------
  process (clk)
    variable step : natural range 1 to 8;
  begin
    if rising_edge(clk) then
      case speed is
        when "00"   => step := 1;
        when "01"   => step := 2;
        when "10"   => step := 4;
        when others => step := 8;
      end case;
      tick <= '0';

      if rst = '1' then
        tick_cnt <= 0;
      elsif pause = '0' then
        if tick_cnt + step >= CLK_HZ then
          tick_cnt <= 0;
          tick     <= '1';
        else
          tick_cnt <= tick_cnt + step;
        end if;
      end if;
    end if;
  end process;

  tick_out <= tick;

  -----------------------------------------------------------------------------
  -- Humor: saida combinacional (Moore) derivada dos atributos
  -----------------------------------------------------------------------------
  process (r_stats)
  begin
    if r_stats(IDX_HEALTH) <= LOW_LEVEL then
      r_mood <= MOOD_DOENTE;
    elsif r_stats(IDX_FOOD) <= LOW_LEVEL or r_stats(IDX_HAPPY) <= LOW_LEVEL
       or r_stats(IDX_ENERGY) <= LOW_LEVEL then
      r_mood <= MOOD_TRISTE;
    else
      r_mood <= MOOD_FELIZ;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Fase da vida: o bichinho evolui ao atingir as idades configuradas
  -----------------------------------------------------------------------------
  stage <= FASE_ADULTO when r_age >= ADULTO_AGE else
           FASE_JOVEM  when r_age >= JOVEM_AGE  else
           FASE_BEBE;

  alert <= '1' when r_mood /= MOOD_FELIZ and st /= ST_OVO and st /= ST_MORTO
           else '0';

  -----------------------------------------------------------------------------
  -- Maquina de estados e atributos
  -----------------------------------------------------------------------------
  process (clk)
    variable v          : stat_array_t;
    variable fire       : boolean;
    variable cnt_food   : cnt_t := 0;
    variable cnt_happy  : cnt_t := 0;
    variable cnt_energy : cnt_t := 0;
    variable cnt_health : cnt_t := 0;
    variable cnt_day    : cnt_t := 0;

    -- divisor de ticks: dispara uma vez a cada "period" chamadas
    procedure tick_div (
      variable cnt    : inout cnt_t;
      constant period : in    positive;
      variable fired  : out   boolean) is
    begin
      if cnt >= period - 1 then
        cnt   := 0;
        fired := true;
      else
        cnt   := cnt + 1;
        fired := false;
      end if;
    end procedure;

    procedure clear_counters is
    begin
      cnt_food   := 0;
      cnt_happy  := 0;
      cnt_energy := 0;
      cnt_health := 0;
      cnt_day    := 0;
    end procedure;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st      <= ST_OVO;
        r_stats <= STATS_RESET;
        r_age   <= 0;
        act_cnt <= 0;
        clear_counters;
      else
        v := r_stats;

        case st is
          ---------------------------------------------------------------------
          when ST_OVO =>
            -- qualquer botao choca o ovo
            if any_btn = '1' then
              st    <= ST_NORMAL;
              v     := STATS_RESET;
              r_age <= 0;
              clear_counters;
            end if;

          ---------------------------------------------------------------------
          when ST_MORTO =>
            -- qualquer botao recomeca o jogo
            if any_btn = '1' then
              st <= ST_OVO;
            end if;

          ---------------------------------------------------------------------
          when others =>
            -- Acoes do jogador
            if st = ST_NORMAL then
              if btn_feed = '1' and v(IDX_FOOD) < STAT_MAX then
                v(IDX_FOOD) := sat_add(v(IDX_FOOD), FEED_GAIN);
                act_cnt     <= ACTION_TICKS;
                st          <= ST_COMENDO;
              elsif btn_play = '1' and v(IDX_ENERGY) >= PLAY_COST then
                v(IDX_HAPPY)  := sat_add(v(IDX_HAPPY), PLAY_GAIN);
                v(IDX_ENERGY) := sat_sub(v(IDX_ENERGY), PLAY_COST);
                v(IDX_FOOD)   := sat_sub(v(IDX_FOOD), 1);
                act_cnt       <= ACTION_TICKS;
                st            <= ST_BRINCANDO;
              elsif btn_sleep = '1' and v(IDX_ENERGY) < STAT_MAX then
                st <= ST_DORMINDO;
              elsif btn_med = '1' and v(IDX_HEALTH) < STAT_MAX then
                v(IDX_HEALTH) := sat_add(v(IDX_HEALTH), MED_GAIN);
                v(IDX_HAPPY)  := sat_sub(v(IDX_HAPPY), MED_COST);
                act_cnt       <= ACTION_TICKS;
                st            <= ST_REMEDIO;
              end if;
            elsif st = ST_DORMINDO then
              if btn_sleep = '1' then
                st <= ST_NORMAL;
              end if;
            end if;

            -- Passagem do tempo
            if tick = '1' then
              -- fim das animacoes de acao
              if st = ST_COMENDO or st = ST_BRINCANDO or st = ST_REMEDIO then
                if act_cnt <= 1 then
                  st <= ST_NORMAL;
                else
                  act_cnt <= act_cnt - 1;
                end if;
              end if;

              -- saciedade: cai mais devagar dormindo
              if st = ST_DORMINDO then
                tick_div(cnt_food, 2 * FOOD_PERIOD, fire);
              else
                tick_div(cnt_food, FOOD_PERIOD, fire);
              end if;
              if fire then
                v(IDX_FOOD) := sat_sub(v(IDX_FOOD), 1);
              end if;

              -- energia e alegria
              if st = ST_DORMINDO then
                tick_div(cnt_energy, SLEEP_PERIOD, fire);
                if fire then
                  v(IDX_ENERGY) := sat_add(v(IDX_ENERGY), 1);
                end if;
              else
                tick_div(cnt_energy, ENERGY_PERIOD, fire);
                if fire then
                  v(IDX_ENERGY) := sat_sub(v(IDX_ENERGY), 1);
                end if;
                tick_div(cnt_happy, HAPPY_PERIOD, fire);
                if fire then
                  v(IDX_HAPPY) := sat_sub(v(IDX_HAPPY), 1);
                end if;
              end if;

              -- saude: cai com algum atributo zerado, sobe com todos bons
              tick_div(cnt_health, HEALTH_PERIOD, fire);
              if fire then
                if v(IDX_FOOD) = 0 or v(IDX_HAPPY) = 0 or v(IDX_ENERGY) = 0 then
                  v(IDX_HEALTH) := sat_sub(v(IDX_HEALTH), 1);
                elsif v(IDX_FOOD) > LOW_LEVEL and v(IDX_HAPPY) > LOW_LEVEL
                  and v(IDX_ENERGY) > LOW_LEVEL then
                  v(IDX_HEALTH) := sat_add(v(IDX_HEALTH), 1);
                end if;
              end if;

              -- idade
              tick_div(cnt_day, DAY_TICKS, fire);
              if fire and r_age < AGE_MAX then
                r_age <= r_age + 1;
              end if;
            end if;

            -- acorda sozinho com a energia cheia
            if st = ST_DORMINDO and v(IDX_ENERGY) = STAT_MAX then
              st <= ST_NORMAL;
            end if;

            -- a morte tem prioridade sobre qualquer outra transicao
            if v(IDX_HEALTH) = 0 then
              st <= ST_MORTO;
            end if;
        end case;

        r_stats <= v;
      end if;
    end if;
  end process;

end architecture rtl;
