# Guia dos arquivos

Explicação de cada arquivo do projeto do bichinho virtual: o que ele faz, o que
tem dentro e como se liga aos outros. Para as regras do jogo e os controles,
veja o [README.md](README.md).

## Visão geral

```
fpga-tamagotchi/
├── src/
│   ├── pet_pkg.vhd         tipos, funções e desenhos (usado por todos)
│   ├── pet_core.vhd        regras do jogo
│   ├── pet_lcd.vhd         LCD: controlador e telas
│   └── bichinho_top.vhd    top-level: liga tudo aos pinos da placa
├── sim/
│   ├── tb_pet_core.vhd     testbench das regras do jogo
│   └── run.do              script de simulação (ModelSim/Questa)
├── bichinho_virtual.qpf    projeto Quartus
├── bichinho_virtual.qsf    configurações e pinagem
├── bichinho_virtual.sdc    restrições de tempo
├── README.md               regras, controles e como compilar
└── ARQUIVOS.md             este guia
```

Como os módulos se ligam:

```
            KEY3..0                SW17, SW0, SW2..1
               │                          │
          ┌────▼─────┐                    │
          │ debounce │ x4                 │
          └────┬─────┘                    │
               │ pulsos                   │ reset, pausa, velocidade
          ┌────▼──────────────────────────▼────┐
          │              pet_core              │
          │  ticks + máquina de estados + atributos
          └────┬───────────────────────────┬───┘
               │ estado, humor, fase,      │
               │ atributos, idade          │
          ┌────▼─────┐               ┌─────▼──────────┐
   SW3 ──►│ pet_lcd  │               │ bichinho_top   │
          │  telas   │               │ HEX e LEDs     │
          └────┬─────┘               └────────────────┘
          ┌────▼───────┐
          │ lcd_driver │──► LCD 16x2
          └────────────┘
```

---

## `src/pet_pkg.vhd` — pacote compartilhado

Um `package` com tudo o que mais de um módulo precisa. Não gera hardware
sozinho: só define nomes, tipos e funções.

| O que | Para que serve |
|---|---|
| `stat_t`, `STAT_MAX` | Um atributo do bichinho, de 0 a 15 |
| `stat_array_t`, `IDX_FOOD`, `IDX_HAPPY`, `IDX_ENERGY`, `IDX_HEALTH` | Os quatro atributos em um vetor, com um índice nomeado para cada |
| `age_t` | Idade em dias, de 0 a 99 |
| `pet_state_t` | Os 7 estados da máquina: ovo, normal, comendo, brincando, dormindo, remédio, morto |
| `pet_mood_t` | Humor: feliz, triste ou doente |
| `pet_stage_t` | Fase da vida: filhote, jovem ou adulto |
| `sat_add`, `sat_sub` | Soma e subtração que param em 15 e em 0, sem "dar a volta" |
| `byte_t`, `lcd_line_t` | Um caractere e uma linha de 16 caracteres do LCD |
| `to_byte`, `to_lcd`, `digit_char` | Convertem letras, textos e números para o código que o LCD entende |
| `SRC_GLYPH_*`, `to_glyph` | Os 9 ícones 5x8: maçã, sorriso, raio, coração, lua, bola, cruz, matinho e brilho |
| `SRC_OVO`, `SRC_FILHOTE`, `SRC_JOVEM`, `SRC_ADULTO`, `SRC_LAPIDE`, `to_sprite`, `SPRITES` | Os 5 desenhos, de 15x16 pontos: ovo, os três gatos e a lápide |
| `sprite_piece` | Recorta um desenho nos 6 caracteres 5x8 que o LCD consegue mostrar |
| `to_seg7` | Converte um número de 0 a 15 para os segmentos do display |

**Desenhos como texto.** Ícones e formas do bichinho são desenhados no código
como linhas de texto, onde `#` é um ponto aceso. Por exemplo, o coração:

```
"....."
".#.#."
"#####"
"#####"
"#####"
".###."
"..#.."
"....."
```

As funções `to_glyph` e `to_sprite` transformam esses desenhos em bits durante
a compilação. Para mudar um desenho, basta editar o texto.

**Por que recortar os desenhos.** O LCD só aceita 8 caracteres personalizados,
cada um de 5x8 pontos. Um bichinho de 15x16 pontos precisa de 3 caracteres de
largura por 2 de altura, ou seja, 6 pedaços. `sprite_piece` devolve o pedaço
pedido; com `hop = true` ela desloca o desenho um ponto para cima, e é isso
que faz o bichinho "pular".

---

## `src/pet_core.vhd` — regras do jogo

O "cérebro" do bichinho. Não sabe nada sobre LCD, displays ou pinos: recebe os
botões e devolve o estado do jogo. Por isso pode ser simulado sozinho.

**Entradas:** clock, reset, pausa, velocidade e um pulso para cada botão
(alimentar, brincar, dormir, remédio).

**Saídas:** estado atual, humor, fase da vida, os quatro atributos, a idade,
um sinal de alerta (algum atributo baixo) e o pulso de tick.

Tem três processos:

1. **Base de tempo.** Um contador gera um pulso (`tick`) a cada segundo de
   jogo. Ele avança 1, 2, 4 ou 8 por ciclo de clock conforme a velocidade, o
   que acelera o tempo sem precisar de vários contadores. A pausa simplesmente
   para o contador.
2. **Humor e fase.** Lógica combinacional. Humor: doente se a saúde está
   baixa, triste se outro atributo está baixo, feliz caso contrário. Fase:
   filhote até 2 dias, jovem a partir de 3, adulto a partir de 6.
3. **Máquina de estados e atributos.** O processo principal. A cada ciclo:
   - trata os botões (só no estado normal; dormindo, só aceita acordar);
   - a cada tick, desconta os atributos conforme os períodos, avalia a saúde
     e conta a idade;
   - acorda o bichinho quando a energia enche;
   - muda para morto se a saúde chegou a zero.

Dentro desse processo há dois procedimentos:

- `tick_div`: divisor de ticks. Chamado uma vez por tick, "dispara" a cada N
  chamadas. É o que faz a saciedade cair a cada 8 ticks, a alegria a cada 10,
  e assim por diante.
- `clear_counters`: zera todos os divisores (usado no reset e ao chocar o ovo).

**Tudo é ajustável por `generic`:** os períodos de queda de cada atributo, as
idades de evolução (`JOVEM_AGE`, `ADULTO_AGE`), a duração das animações, quanto cada ação dá e custa, o nível inicial e o limite
de "atributo baixo". Mudar o equilíbrio do jogo não exige mexer na lógica.

---

## `src/pet_lcd.vhd` — LCD

Tem duas entidades, uma dentro da outra.

### `lcd_driver` — controlador do display

Conversa com o chip do LCD (HD44780), que é lento e exige uma sequência exata
de comandos. É uma máquina de estados com 8 estados:

1. **Espera ao ligar** (50 ms), exigida pelo LCD.
2. **Inicialização:** 6 comandos (modo de 8 bits e 2 linhas, liga o display,
   limpa, direção do cursor).
3. **Laço infinito:** grava os 8 caracteres personalizados (CGRAM), posiciona
   na linha 1, escreve 16 caracteres, posiciona na linha 2, escreve 16
   caracteres, e repete.

Cada byte enviado ocupa uma janela de tempo fixa: os dados são colocados no
início e o pulso de `enable` acontece no meio, garantindo os tempos que o LCD
exige. Como tudo é reescrito sem parar (cerca de 40 vezes por segundo), o
resto do projeto só precisa mudar o texto ou os desenhos e eles aparecem.

### `pet_lcd` — telas

Decide **o que** mostrar. A partir do estado do jogo, monta as duas linhas e
os 8 caracteres personalizados, e entrega ao `lcd_driver`. A entrada `screen`
(chave `SW3`) escolhe entre duas telas:

- **Tela do bichinho.** Em repouso, mostra só o gato, no centro, com matinhos
  no chão; se ele está feliz, pula e aparecem brilhos que mudam de lugar a cada
  segundo. Durante uma ação (e também com o ovo, na evolução e na morte) o
  desenho vai para o canto esquerdo: a linha 1 traz uma mensagem e a linha 2
  traz a animação da ação (maçãs, bola, lua, cruzes).
- **Tela de informações.** Linha 1 com ícone e valor de cada atributo. A linha
  2 alterna a cada 2 segundos entre o humor (`Humor: Feliz`) e a fase com a
  idade (`Jovem     4 dias`), porque as duas coisas não cabem juntas em 16
  colunas.

Como os 8 caracteres personalizados são usados em cada situação:

| Situação | Códigos 0 a 5 | Código 6 | Código 7 |
|---|---|---|---|
| Bichinho no centro | pedaços do desenho | matinho | brilho |
| Bichinho no canto (ação) | pedaços do desenho | ícone da ação | livre |
| Informações | ícones dos atributos (0 a 3) | livre | livre |

Outros detalhes:

- Um contador de quadros (8 quadros de meio segundo) anima as telas. Ele
  recomeça do zero sempre que o estado muda.
- Quando a fase muda, um segundo contador mantém o aviso de evolução por 4
  segundos, nas duas telas.
- A variável `centered` decide a posição do desenho; o mesmo trecho de código
  desenha o gato no centro ou no canto.
- Procedimentos evitam repetição: `put_number` escreve um número de 0 a 99,
  `put_mood` escreve o humor e `put_stage_short` escreve a fase com a idade
  abreviada (`Filhote  2d`).

---

## `src/bichinho_top.vhd` — top-level

Também tem duas entidades.

### `debounce` — filtro de botão

Botões mecânicos "tremem" ao serem apertados e geram vários pulsos falsos. Este
módulo sincroniza o botão com o clock e só aceita a mudança depois de 10 ms
estável. A saída `pressed` é um pulso de um único ciclo por toque, que é o que
o `pet_core` espera.

### `bichinho_top` — ligação com a placa

É a entidade que o Quartus usa como topo; suas portas são os pinos da DE2-115.
Ela não tem lógica de jogo, só conecta as peças:

- sincroniza as chaves `SW17` (reset), `SW0` (pausa), `SW2..1` (velocidade) e
  `SW3` (tela do LCD);
- cria quatro `debounce`, um por `KEY`, com um `generate`;
- instancia o `pet_core` e o `pet_lcd`;
- mostra a idade em `HEX7..6` e os atributos em `HEX3..0`;
- acende os LEDs: vermelhos piscando no alerta, verdes como barra de saúde e
  `LEDG8` invertendo a cada tick.

---

## `sim/tb_pet_core.vhd` — testbench

Testa o `pet_core` sozinho, sem placa. É **autoverificável**: em vez de exigir
que alguém olhe as formas de onda, ele mesmo confere os resultados e imprime
`FALHA: ...` se algo estiver errado.

Para a simulação ser rápida, o `generic` `CLK_HZ` é reduzido para 4, de modo
que um tick de jogo dura 4 ciclos de clock em vez de 50 milhões.

O roteiro do teste:

1. começa como ovo, e o tempo não passa para o ovo;
2. um botão choca o ovo, com saúde cheia e na fase de filhote;
3. alimentar aumenta a saciedade e volta ao normal;
4. brincar aumenta a alegria;
5. dormindo ele não come, recupera energia e acorda sozinho;
6. sem cuidados, entra em alerta e depois morre;
7. um botão recomeça o jogo;
8. o reset volta ao ovo.

O testbench foi executado no Questa e termina sem nenhuma mensagem `FALHA`.

## `sim/run.do` — script de simulação

Comandos para o ModelSim/Questa: compila o pacote, o `pet_core` e o testbench,
abre a simulação, adiciona os sinais principais à janela de ondas e roda até o
fim. Uso: dentro da pasta `sim`, executar `do run.do`.

---

## Arquivos do Quartus

| Arquivo | Conteúdo |
|---|---|
| `bichinho_virtual.qpf` | O projeto em si. É o arquivo que se abre no Quartus. |
| `bichinho_virtual.qsf` | Configurações: o chip da placa (EP4CE115F29C7), a lista de arquivos VHDL, a entidade de topo e a pinagem (qual pino da FPGA liga em cada botão, chave, LED, display e no LCD). |
| `bichinho_virtual.sdc` | Restrições de tempo: informa que o clock é de 50 MHz, para o Quartus verificar se o circuito é rápido o suficiente. |

## Pastas geradas (não vão para o git)

O Quartus cria estas pastas ao compilar. Elas estão no `.gitignore` porque
podem ser geradas de novo a qualquer momento:

| Pasta | Conteúdo |
|---|---|
| `output_files/` | Resultado da compilação. O arquivo que importa é `bichinho_virtual.sof`, que é gravado na placa. Os `.rpt` são relatórios (uso de recursos, pinos, tempo). |
| `db/`, `incremental_db/` | Arquivos internos do Quartus. |
