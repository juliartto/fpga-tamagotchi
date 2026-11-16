-------------------------------------------------------------------------------
-- pet_lcd.vhd
-- Tudo o que envolve o LCD 16x2 da placa, em duas entidades:
--
--   lcd_driver  controlador do HD44780: inicializa o display e reescreve,
--               sem parar, os caracteres personalizados e as duas linhas
--   pet_lcd     monta as telas a partir do estado do jogo e instancia o
--               lcd_driver
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- lcd_driver
--
-- So escreve no LCD (RW sempre em '0'). Cada byte ocupa uma janela de tempo
-- fixa: os dados sao colocados no inicio e o pulso de enable acontece no meio.
--
-- Os 8 caracteres personalizados (glyphs) sao regravados a cada volta, entao
-- quem usa o driver pode trocar os desenhos a qualquer momento.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.pet_pkg.all;

entity lcd_driver is
  generic (
    CLK_HZ     : positive := 50_000_000;
    POWERUP_MS : positive := 50;    -- espera depois de ligar
    INIT_US    : positive := 5000;  -- janela de cada comando de inicializacao
    BYTE_US    : positive := 250    -- janela de cada byte de dados
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    glyphs   : in  glyph_set_t;
    line1    : in  lcd_line_t;
    line2    : in  lcd_line_t;
    lcd_data : out byte_t;
    lcd_rs   : out std_logic;   -- '0' comando, '1' dado
    lcd_rw   : out std_logic;
    lcd_en   : out std_logic
  );
end entity lcd_driver;

architecture rtl of lcd_driver is
  constant POWER_CLKS : natural := (CLK_HZ / 1000) * POWERUP_MS;
  constant INIT_CLKS  : natural := (CLK_HZ / 1_000_000) * INIT_US;
  constant BYTE_CLKS  : natural := (CLK_HZ / 1_000_000) * BYTE_US;

  constant CMD_FUNCTION : byte_t := x"38";  -- 8 bits, 2 linhas, fonte 5x8
  constant CMD_DISPLAY  : byte_t := x"0C";  -- display ligado, sem cursor
  constant CMD_CLEAR    : byte_t := x"01";
  constant CMD_ENTRY    : byte_t := x"06";  -- cursor avanca para a direita
  constant CMD_CGRAM    : byte_t := x"40";  -- endereco 0 da CGRAM
  constant CMD_LINE1    : byte_t := x"80";  -- endereco 0x00 da DDRAM
  constant CMD_LINE2    : byte_t := x"C0";  -- endereco 0x40 da DDRAM

  constant N_INIT : positive := 6;
  constant INIT_CMDS : lcd_text_t(0 to N_INIT - 1) := (
    CMD_FUNCTION, CMD_FUNCTION, CMD_FUNCTION,
    CMD_DISPLAY, CMD_CLEAR, CMD_ENTRY);

  constant N_GLYPH_BYTES : positive := N_GLYPHS * GLYPH_ROWS;

  type state_t is (ST_POWERUP, ST_INIT, ST_CGRAM_ADDR, ST_CGRAM_DATA,
                   ST_LINE1_ADDR, ST_LINE1_DATA, ST_LINE2_ADDR, ST_LINE2_DATA);

  signal st    : state_t := ST_POWERUP;
  signal idx   : natural range 0 to N_GLYPH_BYTES - 1 := 0;
  signal timer : natural range 0 to POWER_CLKS := 0;

  signal cur_data : byte_t;
  signal cur_rs   : std_logic;
begin

  assert POWER_CLKS >= INIT_CLKS and INIT_CLKS >= BYTE_CLKS and BYTE_CLKS >= 4
    report "lcd_driver: tempos incompativeis com CLK_HZ"
    severity failure;

  lcd_rw <= '0';

  -----------------------------------------------------------------------------
  -- Byte correspondente ao passo atual
  -----------------------------------------------------------------------------
  process (st, idx, glyphs, line1, line2)
  begin
    cur_rs   <= '0';
    cur_data <= (others => '0');

    case st is
      when ST_POWERUP    => null;
      when ST_INIT       => cur_data <= INIT_CMDS(idx mod N_INIT);
      when ST_CGRAM_ADDR => cur_data <= CMD_CGRAM;
      when ST_CGRAM_DATA =>
        cur_rs   <= '1';
        cur_data <= "000" & glyphs(idx / GLYPH_ROWS)(idx mod GLYPH_ROWS);
      when ST_LINE1_ADDR => cur_data <= CMD_LINE1;
      when ST_LINE1_DATA =>
        cur_rs   <= '1';
        cur_data <= line1(idx mod LCD_COLS);
      when ST_LINE2_ADDR => cur_data <= CMD_LINE2;
      when ST_LINE2_DATA =>
        cur_rs   <= '1';
        cur_data <= line2(idx mod LCD_COLS);
    end case;
  end process;

  -----------------------------------------------------------------------------
  -- Maquina de estados e temporizacao
  -----------------------------------------------------------------------------
  process (clk)
    variable slot : natural range 0 to POWER_CLKS;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st     <= ST_POWERUP;
        idx    <= 0;
        timer  <= 0;
        lcd_en <= '0';
      elsif st = ST_POWERUP then
        lcd_en <= '0';
        if timer = POWER_CLKS then
          timer <= 0;
          idx   <= 0;
          st    <= ST_INIT;
        else
          timer <= timer + 1;
        end if;
      else
        if st = ST_INIT then
          slot := INIT_CLKS;
        else
          slot := BYTE_CLKS;
        end if;

        -- dados no inicio da janela, enable no segundo quarto
        if timer = 0 then
          lcd_data <= cur_data;
          lcd_rs   <= cur_rs;
        end if;

        if timer >= slot / 4 and timer < slot / 2 then
          lcd_en <= '1';
        else
          lcd_en <= '0';
        end if;

        if timer < slot - 1 then
          timer <= timer + 1;
        else
          -- fim da janela: proximo passo
          timer <= 0;
          case st is
            when ST_INIT =>
              if idx = N_INIT - 1 then
                st <= ST_CGRAM_ADDR;
              else
                idx <= idx + 1;
              end if;

            when ST_CGRAM_ADDR =>
              idx <= 0;
              st  <= ST_CGRAM_DATA;

            when ST_CGRAM_DATA =>
              if idx = N_GLYPH_BYTES - 1 then
                st <= ST_LINE1_ADDR;
              else
                idx <= idx + 1;
              end if;

            when ST_LINE1_ADDR =>
              idx <= 0;
              st  <= ST_LINE1_DATA;

            when ST_LINE1_DATA =>
              if idx = LCD_COLS - 1 then
                st <= ST_LINE2_ADDR;
              else
                idx <= idx + 1;
              end if;

            when ST_LINE2_ADDR =>
              idx <= 0;
              st  <= ST_LINE2_DATA;

            when ST_LINE2_DATA =>
              -- fim da volta: recomeca pelos caracteres personalizados
              if idx = LCD_COLS - 1 then
                st <= ST_CGRAM_ADDR;
              else
                idx <= idx + 1;
              end if;

            when others =>
              st <= ST_POWERUP;
          end case;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;

-------------------------------------------------------------------------------
-- pet_lcd
--
-- Ha duas telas, escolhidas pela entrada "screen":
--
--   screen = '0'  TELA DO BICHINHO
--     O desenho do bichinho ocupa 3 colunas x 2 linhas, a esquerda. O desenho
--     depende da fase (bebe, jovem, adulto); ovo e lapide tem desenho proprio.
--       linha 1: mensagem ("Feliz", "Com fome", "Nham nham", "Evoluiu!"...)
--       linha 2: fase e idade ("Jovem  dia 4") ou a animacao da acao
--
--   screen = '1'  TELA DE ATRIBUTOS
--       linha 1: icone e valor (0 a 15) de cada atributo
--       linha 2: fase e idade
--
-- Os 8 caracteres personalizados mudam conforme a tela: na do bichinho, 6 sao
-- os pedacos do desenho e 1 e o icone da acao; na de atributos, 4 sao os
-- icones. A animacao recomeca do quadro 0 sempre que o estado muda.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.pet_pkg.all;

entity pet_lcd is
  generic (
    CLK_HZ        : positive := 50_000_000;
    LOW_LEVEL     : stat_t   := 4;
    EVOLVE_FRAMES : positive := 8    -- duracao do aviso "Evoluiu!"
  );
  port (
    clk      : in  std_logic;
    screen   : in  std_logic;   -- '0' bichinho, '1' atributos
    state    : in  pet_state_t;
    mood     : in  pet_mood_t;
    stage    : in  pet_stage_t;
    stats    : in  stat_array_t;
    age      : in  age_t;
    lcd_data : out byte_t;
    lcd_rs   : out std_logic;
    lcd_rw   : out std_logic;
    lcd_en   : out std_logic
  );
end entity pet_lcd;

architecture rtl of pet_lcd is
  constant SPACE : byte_t := to_byte(' ');

  -- Tela do bichinho: o texto comeca depois do desenho e de um espaco
  constant TEXT_COL : positive := SPR_CHARS_W + 1;
  constant TEXT_LEN : positive := LCD_COLS - TEXT_COL;

  -- codigo do caractere personalizado usado para o icone da acao
  constant ACT_GLYPH : natural := SPR_PIECES;

  -- cada quadro da animacao dura meio segundo
  constant N_FRAMES  : positive := 8;
  constant ANIM_CLKS : positive := CLK_HZ / 2;

  signal anim_cnt   : natural range 0 to ANIM_CLKS - 1 := 0;
  signal frame      : natural range 0 to N_FRAMES - 1  := 0;
  signal state_prev : pet_state_t := ST_OVO;
  signal stage_prev : pet_stage_t := FASE_BEBE;
  signal evolve_cnt : natural range 0 to EVOLVE_FRAMES := 0;

  signal glyphs : glyph_set_t := (others => GLYPH_BLANK);
  signal line1  : lcd_line_t  := (others => SPACE);
  signal line2  : lcd_line_t  := (others => SPACE);

  -- codigo do caractere personalizado "g" da CGRAM
  function glyph_char (g : natural) return byte_t is
  begin
    return to_byte(character'val(g));
  end function;

  -- nome da fase, com 7 colunas
  function stage_name (s : pet_stage_t) return lcd_text_t is
  begin
    case s is
      when FASE_BEBE  => return to_lcd("Bebe", 7);
      when FASE_JOVEM => return to_lcd("Jovem", 7);
      when others     => return to_lcd("Adulto", 7);
    end case;
  end function;
begin

  -- o LCD nao tem reset: ele so precisa ser inicializado ao ligar
  u_driver : entity work.lcd_driver
    generic map (
      CLK_HZ => CLK_HZ)
    port map (
      clk      => clk,
      rst      => '0',
      glyphs   => glyphs,
      line1    => line1,
      line2    => line2,
      lcd_data => lcd_data,
      lcd_rs   => lcd_rs,
      lcd_rw   => lcd_rw,
      lcd_en   => lcd_en);

  -----------------------------------------------------------------------------
  -- Animacao: contador de quadros, reiniciado a cada mudanca de estado.
  -- Ao mudar de fase, evolve_cnt mantem o aviso "Evoluiu!" por alguns quadros.
  -----------------------------------------------------------------------------
  process (clk)
    variable next_frame : boolean;
  begin
    if rising_edge(clk) then
      state_prev <= state;
      stage_prev <= stage;
      next_frame := false;

      if state /= state_prev then
        anim_cnt <= 0;
        frame    <= 0;
      elsif anim_cnt = ANIM_CLKS - 1 then
        anim_cnt   <= 0;
        next_frame := true;
        if frame = N_FRAMES - 1 then
          frame <= 0;
        else
          frame <= frame + 1;
        end if;
      else
        anim_cnt <= anim_cnt + 1;
      end if;

      -- um novo bichinho volta a ser bebe: isso nao conta como evolucao
      if stage /= stage_prev and stage /= FASE_BEBE then
        evolve_cnt <= EVOLVE_FRAMES;
      elsif state = ST_OVO or state = ST_MORTO then
        evolve_cnt <= 0;
      elsif next_frame and evolve_cnt > 0 then
        evolve_cnt <= evolve_cnt - 1;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Telas
  -----------------------------------------------------------------------------
  process (clk)
    variable l1, l2 : lcd_line_t;
    variable g      : glyph_set_t;
    variable msg    : lcd_text_t(0 to TEXT_LEN - 1);
    variable info   : lcd_text_t(0 to TEXT_LEN - 1);
    variable spr    : sprite_id_t;
    variable odd    : boolean;
    variable hop    : boolean;

    -- escreve um numero de 0 a 99 em 2 colunas, sem zero a esquerda
    procedure put_number (
      variable txt : inout lcd_text_t;
      constant pos : in    natural;
      constant n   : in    natural) is
    begin
      if n >= 10 then
        txt(pos) := digit_char(n / 10);
      else
        txt(pos) := SPACE;
      end if;
      txt(pos + 1) := digit_char(n mod 10);
    end procedure;

    -- escreve "fase dia NN" (12 colunas) a partir de pos
    procedure put_stage_age (
      variable txt : inout lcd_text_t;
      constant pos : in    natural) is
    begin
      txt(pos to pos + 6)     := stage_name(stage);
      txt(pos + 7 to pos + 9) := to_lcd("dia", 3);
      put_number(txt, pos + 10, age);
    end procedure;
  begin
    if rising_edge(clk) then
      odd := (frame mod 2 = 1);
      l1  := (others => SPACE);
      l2  := (others => SPACE);
      g   := (others => GLYPH_BLANK);

      if screen = '0' then
        -----------------------------------------------------------------------
        -- TELA DO BICHINHO
        -----------------------------------------------------------------------
        msg  := (others => SPACE);
        info := (others => SPACE);
        hop  := false;

        -- desenho conforme a fase da vida
        case stage is
          when FASE_BEBE   => spr := SPR_BEBE;
          when FASE_JOVEM  => spr := SPR_JOVEM;
          when FASE_ADULTO => spr := SPR_ADULTO;
        end case;

        case state is
          when ST_OVO =>
            spr  := SPR_OVO;
            hop  := odd;
            msg  := to_lcd("Um ovo!", TEXT_LEN);
            info := to_lcd("Aperte botao", TEXT_LEN);

          when ST_NORMAL =>
            case mood is
              when MOOD_FELIZ =>
                hop := odd;   -- so pula quando esta feliz
                msg := to_lcd("Feliz", TEXT_LEN);
              when MOOD_TRISTE =>
                if stats(IDX_FOOD) <= LOW_LEVEL then
                  msg := to_lcd("Com fome", TEXT_LEN);
                elsif stats(IDX_ENERGY) <= LOW_LEVEL then
                  msg := to_lcd("Cansado", TEXT_LEN);
                else
                  msg := to_lcd("Entediado", TEXT_LEN);
                end if;
              when MOOD_DOENTE =>
                msg := to_lcd("Doente!", TEXT_LEN);
            end case;

            if evolve_cnt > 0 then
              hop := odd;
              msg := to_lcd("Evoluiu!", TEXT_LEN);
            end if;
            put_stage_age(info, 0);

          when ST_COMENDO =>
            hop := odd;
            msg := to_lcd("Nham nham", TEXT_LEN);
            g(ACT_GLYPH) := STAT_GLYPHS(IDX_FOOD);
            -- tres macas, comidas uma a cada dois quadros
            for k in 0 to 2 loop
              if frame / 2 <= k then
                info(2 * k) := glyph_char(ACT_GLYPH);
              end if;
            end loop;

          when ST_BRINCANDO =>
            hop := odd;
            msg := to_lcd("Brincando!", TEXT_LEN);
            g(ACT_GLYPH) := GLYPH_BALL;
            -- a bola anda uma coluna por quadro
            info(frame) := glyph_char(ACT_GLYPH);

          when ST_DORMINDO =>
            msg := to_lcd("Dormindo", TEXT_LEN);
            g(ACT_GLYPH) := GLYPH_MOON;
            info(0) := glyph_char(ACT_GLYPH);
            case frame mod 4 is
              when 0      => info(2 to 6) := to_lcd("z", 5);
              when 1      => info(2 to 6) := to_lcd("z Z", 5);
              when 2      => info(2 to 6) := to_lcd("z Z z", 5);
              when others => null;
            end case;

          when ST_REMEDIO =>
            msg := to_lcd("Remedio", TEXT_LEN);
            g(ACT_GLYPH) := GLYPH_CROSS;
            if not odd then
              info(0) := glyph_char(ACT_GLYPH);
              info(2) := glyph_char(ACT_GLYPH);
              info(4) := glyph_char(ACT_GLYPH);
            end if;

          when ST_MORTO =>
            spr  := SPR_LAPIDE;
            msg  := to_lcd("Morreu...", TEXT_LEN);
            info := to_lcd("com    dias", TEXT_LEN);
            put_number(info, 4, age);
        end case;

        -- o desenho vira 6 caracteres personalizados (codigos 0 a 5)
        for p in 0 to SPR_PIECES - 1 loop
          g(p) := sprite_piece(SPRITES(spr), p, hop);
        end loop;
        for c in 0 to SPR_CHARS_W - 1 loop
          l1(c) := glyph_char(c);
          l2(c) := glyph_char(SPR_CHARS_W + c);
        end loop;

        l1(TEXT_COL to LCD_COLS - 1) := msg;
        l2(TEXT_COL to LCD_COLS - 1) := info;

      else
        -----------------------------------------------------------------------
        -- TELA DE ATRIBUTOS
        -----------------------------------------------------------------------
        case state is
          when ST_OVO =>
            l1 := to_lcd("Um ovo!", LCD_COLS);
            l2 := to_lcd("Aperte um botao", LCD_COLS);

          when ST_MORTO =>
            l1 := to_lcd("Morreu...", LCD_COLS);
            l2 := to_lcd("Viveu    dias", LCD_COLS);
            put_number(l2, 6, age);

          when others =>
            -- icone (codigos 0 a 3) e valor de cada atributo
            for i in 0 to N_STATS - 1 loop
              g(i)      := STAT_GLYPHS(i);
              l1(4 * i) := glyph_char(i);
              put_number(l1, 4 * i + 1, stats(i));
            end loop;
            put_stage_age(l2, 0);
        end case;
      end if;

      glyphs <= g;
      line1  <= l1;
      line2  <= l2;
    end if;
  end process;

end architecture rtl;
