-------------------------------------------------------------------------------
-- pet_pkg.vhd
-- Tipos, constantes, desenhos e funcoes compartilhadas do bichinho virtual.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pet_pkg is

  -----------------------------------------------------------------------------
  -- Atributos do bichinho
  -----------------------------------------------------------------------------
  constant STAT_MAX : positive := 15;
  subtype stat_t is natural range 0 to STAT_MAX;

  constant AGE_MAX : positive := 99;
  subtype age_t is natural range 0 to AGE_MAX;

  constant N_STATS    : positive := 4;
  constant IDX_FOOD   : natural  := 0;  -- saciedade
  constant IDX_HAPPY  : natural  := 1;  -- alegria
  constant IDX_ENERGY : natural  := 2;  -- energia
  constant IDX_HEALTH : natural  := 3;  -- saude
  type stat_array_t is array (0 to N_STATS - 1) of stat_t;

  -- Estados da maquina principal
  type pet_state_t is (ST_OVO, ST_NORMAL, ST_COMENDO, ST_BRINCANDO,
                       ST_DORMINDO, ST_REMEDIO, ST_MORTO);

  -- Humor (derivado dos atributos, usado so para exibir)
  type pet_mood_t is (MOOD_FELIZ, MOOD_TRISTE, MOOD_DOENTE);

  -- Fase da vida (derivada da idade): o bichinho muda de forma ao evoluir
  type pet_stage_t is (FASE_BEBE, FASE_JOVEM, FASE_ADULTO);

  -- soma e subtracao que param em STAT_MAX e em 0
  function sat_add (v : stat_t; n : natural) return stat_t;
  function sat_sub (v : stat_t; n : natural) return stat_t;

  -----------------------------------------------------------------------------
  -- LCD de caracteres 16x2 (HD44780): texto
  -----------------------------------------------------------------------------
  constant LCD_COLS : positive := 16;

  subtype byte_t is std_logic_vector(7 downto 0);
  type lcd_text_t is array (natural range <>) of byte_t;
  subtype lcd_line_t is lcd_text_t(0 to LCD_COLS - 1);

  function to_byte (c : character) return byte_t;
  -- converte um texto para "len" caracteres, completando com espacos
  function to_lcd (s : string; len : positive) return lcd_text_t;
  function digit_char (d : natural range 0 to 9) return byte_t;

  -----------------------------------------------------------------------------
  -- LCD: caracteres personalizados (CGRAM)
  -- O LCD aceita 8 caracteres desenhados pelo usuario, de 5x8 pontos, nos
  -- codigos 0 a 7. Os desenhos sao escritos como texto ('#' = ponto aceso).
  -----------------------------------------------------------------------------
  constant N_GLYPHS   : positive := 8;
  constant GLYPH_ROWS : positive := 8;
  constant GLYPH_COLS : positive := 5;

  subtype glyph_row_t is std_logic_vector(GLYPH_COLS - 1 downto 0);
  type glyph_t is array (0 to GLYPH_ROWS - 1) of glyph_row_t;
  type glyph_src_t is array (0 to GLYPH_ROWS - 1) of string(1 to GLYPH_COLS);
  type glyph_set_t is array (0 to N_GLYPHS - 1) of glyph_t;
  type stat_glyphs_t is array (0 to N_STATS - 1) of glyph_t;

  constant GLYPH_BLANK : glyph_t := (others => (others => '0'));

  function to_glyph (src : glyph_src_t) return glyph_t;

  constant SRC_GLYPH_FOOD : glyph_src_t := (  -- maca
    "...#.",
    "..#..",
    ".###.",
    "#####",
    "#####",
    "#####",
    ".###.",
    ".....");

  constant SRC_GLYPH_HAPPY : glyph_src_t := (  -- sorriso
    ".....",
    ".#.#.",
    ".#.#.",
    ".....",
    "#...#",
    ".###.",
    ".....",
    ".....");

  constant SRC_GLYPH_ENERGY : glyph_src_t := (  -- raio
    "...#.",
    "..#..",
    ".#...",
    "#####",
    "...#.",
    "..#..",
    ".#...",
    ".....");

  constant SRC_GLYPH_HEALTH : glyph_src_t := (  -- coracao
    ".....",
    ".#.#.",
    "#####",
    "#####",
    "#####",
    ".###.",
    "..#..",
    ".....");

  constant SRC_GLYPH_MOON : glyph_src_t := (  -- lua
    "..##.",
    ".##..",
    "##...",
    "##...",
    "##...",
    ".##..",
    "..##.",
    ".....");

  constant SRC_GLYPH_BALL : glyph_src_t := (  -- bola
    ".....",
    ".###.",
    "#####",
    "#####",
    "#####",
    ".###.",
    ".....",
    ".....");

  constant SRC_GLYPH_CROSS : glyph_src_t := (  -- cruz do remedio
    ".....",
    "..#..",
    "..#..",
    "#####",
    "..#..",
    "..#..",
    ".....",
    ".....");

  -- valores definidos no corpo do pacote (dependem de to_glyph)
  constant STAT_GLYPHS : stat_glyphs_t;   -- icones dos atributos, ordem IDX_*
  constant GLYPH_MOON  : glyph_t;
  constant GLYPH_BALL  : glyph_t;
  constant GLYPH_CROSS : glyph_t;

  -----------------------------------------------------------------------------
  -- LCD: desenhos do bichinho
  -- Cada desenho ocupa 3 caracteres de largura por 2 linhas (15x16 pontos),
  -- ou seja, 6 dos 8 caracteres personalizados.
  -----------------------------------------------------------------------------
  constant SPR_CHARS_W : positive := 3;
  constant SPR_CHARS_H : positive := 2;
  constant SPR_PIECES  : positive := SPR_CHARS_W * SPR_CHARS_H;
  constant SPR_COLS    : positive := SPR_CHARS_W * GLYPH_COLS;
  constant SPR_ROWS    : positive := SPR_CHARS_H * GLYPH_ROWS;

  subtype sprite_row_t is std_logic_vector(SPR_COLS - 1 downto 0);
  type sprite_t is array (0 to SPR_ROWS - 1) of sprite_row_t;
  type sprite_src_t is array (0 to SPR_ROWS - 1) of string(1 to SPR_COLS);

  type sprite_id_t is (SPR_OVO, SPR_BEBE, SPR_JOVEM, SPR_ADULTO, SPR_LAPIDE);
  type sprite_rom_t is array (sprite_id_t) of sprite_t;

  function to_sprite (src : sprite_src_t) return sprite_t;

  -- recorta o pedaco "piece" (0 a 5, da esquerda para a direita e de cima
  -- para baixo) de um desenho; com hop = true o desenho sobe um ponto
  function sprite_piece (spr : sprite_t; piece : natural; hop : boolean)
    return glyph_t;

  constant SRC_OVO : sprite_src_t := (
    "...............",
    "......###......",
    ".....#...#.....",
    "....#.....#....",
    "....#.##..#....",
    "...#..##...#...",
    "...#.......#...",
    "...#....##.#...",
    "...#....##.#...",
    "...#.......#...",
    "...#.##....#...",
    "...#.##....#...",
    "....#.....#....",
    "....#.....#....",
    ".....#...#.....",
    "......###......");

  -- bebe: pequeno e redondo
  constant SRC_BEBE : sprite_src_t := (
    "...............",
    "...............",
    "...............",
    "...............",
    "...............",
    "...............",
    "...............",
    ".....#####.....",
    "....#.....#....",
    "...#.#...#.#...",
    "...#.#...#.#...",
    "...#.......#...",
    "...#..###..#...",
    "....#.....#....",
    ".....#####.....",
    "...............");

  -- jovem: maior, com orelhas e pes
  constant SRC_JOVEM : sprite_src_t := (
    "...............",
    "...............",
    "...............",
    "..##.......##..",
    "..#.#.....#.#..",
    "..#..#####..#..",
    "..#.........#..",
    "..#..#...#..#..",
    "..#..#...#..#..",
    "..#.........#..",
    "..#..#...#..#..",
    "..#...###...#..",
    "...#.......#...",
    "....#######....",
    "....#.....#....",
    "...##.....##...");

  -- adulto: ocupa o desenho todo, com coroa e bracos
  constant SRC_ADULTO : sprite_src_t := (
    "...............",
    "..#..#...#..#..",
    "..##.##.##.##..",
    "..###########..",
    ".#...........#.",
    ".#..##...##..#.",
    ".#..##...##..#.",
    "##...........##",
    "#.#.........#.#",
    "#.#..#...#..#.#",
    "..#...###...#..",
    "..#.........#..",
    "..#.........#..",
    "...#########...",
    "...##.....##...",
    "..###.....###..");

  constant SRC_LAPIDE : sprite_src_t := (
    "...............",
    ".....#####.....",
    "...##.....##...",
    "..#.........#..",
    "..#....#....#..",
    "..#....#....#..",
    "..#..#####..#..",
    "..#....#....#..",
    "..#....#....#..",
    "..#....#....#..",
    "..#.........#..",
    "..#.........#..",
    "..#.........#..",
    "..#.........#..",
    ".#############.",
    "###############");

  constant SPRITES : sprite_rom_t;

  -----------------------------------------------------------------------------
  -- Display de 7 segmentos (ativo em nivel baixo, ordem "gfedcba")
  -----------------------------------------------------------------------------
  subtype seg7_t is std_logic_vector(6 downto 0);
  constant SEG7_OFF : seg7_t := "1111111";

  function to_seg7 (digit : natural range 0 to 15) return seg7_t;

end package pet_pkg;

package body pet_pkg is

  function sat_add (v : stat_t; n : natural) return stat_t is
  begin
    if v + n > STAT_MAX then
      return STAT_MAX;
    end if;
    return v + n;
  end function;

  function sat_sub (v : stat_t; n : natural) return stat_t is
  begin
    if n > v then
      return 0;
    end if;
    return v - n;
  end function;

  function to_byte (c : character) return byte_t is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;

  function to_lcd (s : string; len : positive) return lcd_text_t is
    variable txt : lcd_text_t(0 to len - 1) := (others => to_byte(' '));
  begin
    for i in 0 to len - 1 loop
      if i < s'length then
        txt(i) := to_byte(s(s'low + i));
      end if;
    end loop;
    return txt;
  end function;

  function digit_char (d : natural range 0 to 9) return byte_t is
  begin
    return std_logic_vector(to_unsigned(character'pos('0') + d, 8));
  end function;

  function to_glyph (src : glyph_src_t) return glyph_t is
    variable g : glyph_t;
  begin
    for row in 0 to GLYPH_ROWS - 1 loop
      for col in 0 to GLYPH_COLS - 1 loop
        if src(row)(col + 1) = '#' then
          g(row)(GLYPH_COLS - 1 - col) := '1';
        else
          g(row)(GLYPH_COLS - 1 - col) := '0';
        end if;
      end loop;
    end loop;
    return g;
  end function;

  constant STAT_GLYPHS : stat_glyphs_t := (
    IDX_FOOD   => to_glyph(SRC_GLYPH_FOOD),
    IDX_HAPPY  => to_glyph(SRC_GLYPH_HAPPY),
    IDX_ENERGY => to_glyph(SRC_GLYPH_ENERGY),
    IDX_HEALTH => to_glyph(SRC_GLYPH_HEALTH));

  constant GLYPH_MOON  : glyph_t := to_glyph(SRC_GLYPH_MOON);
  constant GLYPH_BALL  : glyph_t := to_glyph(SRC_GLYPH_BALL);
  constant GLYPH_CROSS : glyph_t := to_glyph(SRC_GLYPH_CROSS);

  function to_sprite (src : sprite_src_t) return sprite_t is
    variable spr : sprite_t;
  begin
    for row in 0 to SPR_ROWS - 1 loop
      for col in 0 to SPR_COLS - 1 loop
        if src(row)(col + 1) = '#' then
          spr(row)(SPR_COLS - 1 - col) := '1';
        else
          spr(row)(SPR_COLS - 1 - col) := '0';
        end if;
      end loop;
    end loop;
    return spr;
  end function;

  function sprite_piece (spr : sprite_t; piece : natural; hop : boolean)
    return glyph_t is
    constant CHAR_COL : natural := piece mod SPR_CHARS_W;
    constant CHAR_ROW : natural := piece / SPR_CHARS_W;
    -- bit mais a esquerda deste pedaco dentro da linha do desenho
    constant MSB      : natural := SPR_COLS - 1 - CHAR_COL * GLYPH_COLS;
    variable g   : glyph_t := GLYPH_BLANK;
    variable src : natural;
  begin
    for row in 0 to GLYPH_ROWS - 1 loop
      src := CHAR_ROW * GLYPH_ROWS + row;
      if hop then
        src := src + 1;
      end if;
      if src < SPR_ROWS then
        g(row) := spr(src)(MSB downto MSB - GLYPH_COLS + 1);
      end if;
    end loop;
    return g;
  end function;

  constant SPRITES : sprite_rom_t := (
    SPR_OVO    => to_sprite(SRC_OVO),
    SPR_BEBE   => to_sprite(SRC_BEBE),
    SPR_JOVEM  => to_sprite(SRC_JOVEM),
    SPR_ADULTO => to_sprite(SRC_ADULTO),
    SPR_LAPIDE => to_sprite(SRC_LAPIDE));

  function to_seg7 (digit : natural range 0 to 15) return seg7_t is
  begin
    case digit is
      when 0      => return "1000000";
      when 1      => return "1111001";
      when 2      => return "0100100";
      when 3      => return "0110000";
      when 4      => return "0011001";
      when 5      => return "0010010";
      when 6      => return "0000010";
      when 7      => return "1111000";
      when 8      => return "0000000";
      when 9      => return "0010000";
      when 10     => return "0001000";
      when 11     => return "0000011";
      when 12     => return "1000110";
      when 13     => return "0100001";
      when 14     => return "0000110";
      when others => return "0001110";
    end case;
  end function;

end package body pet_pkg;
