# `spi_exe_unit_1`: slave SPI z ALU

Plik: `MODEL/SPI_EXE_UNIT_1/spi_exe_unit_1.sv` (171 linii). Katalog zawiera też netlistę ALU (`exe_unit_1_rtl.sv`) oraz własne kopie `shifter.sv` i `watchdog.sv`.

## Parametry

| Nazwa | Rodzaj | Wartość | Opis |
|---|---|---|---|
| `BITS` | `parameter` | 28 | Długość ramki / rejestru wyjściowego. **Nie można go zmienić**, bo wypełnienie `{16{1'b0}}` jest na sztywno |
| `M` | `localparam` | 8 | Szerokość argumentów, wyniku i rejestru wejściowego |
| `N` | `localparam` | 4 | Zadeklarowany, nieużywany (szerokość opcode'u) |

## Porty

| Port | Kier. | Opis |
|---|---|---|
| `i_rst` | in | Reset asynchroniczny, aktywny `0` |
| `i_sclk` | in | SCLK. **Jedyny zegar** modułu |
| `i_mosi` | in | MOSI |
| `o_miso` | out | MISO. Zawsze sterowane, nie jest trójstanowe |
| `i_cs` | in | CS, aktywny `0`. Sprawdzany tylko w stanie `READY` |

## Struktura

```
 i_mosi ──► ┌─────────────────┐ o_data[7:0] (s_data_next)
            │ shift_in #(8)   ├──────┬──────────────┬──────────────┐
            └─────────────────┘      ▼              ▼              ▼
                                ┌─────────┐    ┌─────────┐    ┌──────────┐
                  argA_enable ─►│ s_argA  │    │ s_argB  │◄─  │ s_oper   │◄─ oper_enable
                                └────┬────┘    └────┬────┘    └────┬─────┘
                                     │  argB_enable─┘              │ [7:4]
                                     ▼              ▼              ▼
                               ┌───────────────────────────────────────┐
                               │   exe_unit_rtl (ALU)                  │  (kombinacyjne)
                               └───────────┬──────────────┬────────────┘
                                 s_result_next[7:0]  s_flags_next[3:0]
                                           ▼              ▼
                                  (latch, przezroczysty w STORE_RESULT)
                                     s_result         s_flags
                                           └──────┬───────┘
                                                  ▼  {s_result, s_flags, 16'b0}
                                         ┌─────────────────┐
                            s_wrt_out ──►│ shift_out #(28) ├──► o_miso (MSB)
                                         └─────────────────┘
                     ┌──────────────┐
          s_cycles ─►│ watchdog #(4)├──► s_inter ──► FSM
          s_we     ─►└──────────────┘
```

### Instancje

| Instancja | Moduł | Połączenia |
|---|---|---|
| `exe1` | `exe_unit_rtl` (netlista ALU) | `i_argA=s_argA`, `i_argB=s_argB`, `i_oper=s_oper[7:4]`, `o_result=s_result_next`, flagi → `s_flags_next[3:0]` |
| `shift_in` | `shifter #(.N(8))` | `i_bit=i_mosi`, `i_en=s_en_in`, `i_wrt=s_wrt_in` (zawsze 0), `o_data=s_data_next`. **`i_data` i `o_bit` niepodłączone** |
| `shift_out` | `shifter #(.N(28))` | `i_data={s_result, s_flags, 16'b0}`, `i_en=s_en_out`, `i_wrt=s_wrt_out`, `o_bit=o_miso`. **`i_bit` niepodłączone** |
| `counter` | `watchdog #(.N(4))` | `i_cycles=s_cycles`, `i_we=s_we`, `o_inter=s_inter` |

### Rejestry (↑ `i_sclk`, reset asynchroniczny `0`)

| Blok | Rejestr | Zapis gdy | Wartość |
|---|---|---|---|
| `FSM` | `s_state` | zawsze | `s_state_next` |
| `regA` | `s_argA[7:0]` | `argA_enable` | `s_argA_next` (= `s_data_next`) |
| `regB` | `s_argB[7:0]` | `argB_enable` | `s_argB_next` |
| `regOper` | `s_oper[7:0]` | `oper_enable` | `s_oper_next`. Do ALU idą tylko bity `[7:4]` |

`s_result`, `s_flags`, `s_argA_next`, `s_argB_next` i `s_oper_next` są przypisywane w `always @(*)` tylko w niektórych stanach, więc Yosys **syntezuje z nich 5 latchy**.

## Maszyna stanów

Kodowanie: 3 bity.

```
            !i_cs            s_inter          s_inter           s_inter
 ┌─────────┐ ──► ┌──────────┐ ──► ┌──────────┐ ──► ┌─────────────┐ ──► ┌────────────────┐
 │ READY 0 │     │ LOAD_A 1 │     │ LOAD_B 2 │     │ LOAD_OPER 3 │     │ STORE_RESULT 4 │
 └─────────┘     └──────────┘     └──────────┘     └─────────────┘     └───────┬────────┘
      ▲                                                                        │ (zawsze)
      └────────────────────────────────────────────────────────────────────────┘
```

| Stan | Warunek przejścia | Akcje (kombinacyjne) |
|---|---|---|
| `READY` | `!i_cs` → `LOAD_A` | Bez CS: `s_en_in = s_en_out = 0` (rejestry stoją). Przy `!i_cs`: `en=1`, `s_cycles=8`, `s_we=1` (ładowanie licznika) |
| `LOAD_A` | `s_inter` → `LOAD_B` | Przy `s_inter`: `argA_enable=1`, `s_argA_next = s_data_next` |
| `LOAD_B` | `s_inter` → `LOAD_OPER` | Przy `s_inter`: `argB_enable=1`, `s_argB_next = s_data_next` |
| `LOAD_OPER` | `s_inter` → `STORE_RESULT` | Przy `s_inter`: `oper_enable=1`, `s_oper_next = s_data_next` |
| `STORE_RESULT` | zawsze → `READY` | `s_wrt_out=1` (wpis równoległy do `shift_out`), `s_result = s_result_next`, `s_flags = s_flags_next` (latch) |
| inne | → `READY` | — |

Wartości domyślne na początku bloku: `s_en_in = s_en_out = 1`, `s_wrt_in = s_wrt_out = 0`, `s_cycles = 0`, `s_we = 0`, wszystkie `*_enable = 0`.

Poza `READY` oba rejestry przesuwne są stale włączone:

- `shift_in` zbiera MOSI;
- `shift_out` wysuwa odpowiedź na MISO.

Stan `i_cs` poza `READY` jest ignorowany.

## Przebieg ramki w slave'ie

Szczegółowa tabela zbocze po zboczu jest w [protokol_spi.md §4.3](protokol_spi.md#43-slave-co-dzieje-się-na-każdym-zboczu-). W skrócie:

1. ↑#1: CS aktywny → `LOAD_A`, licznik ← 8.
2. ↑#2 … ↑#9: 8 bitów A. ↑#10: zapis A (bit d19 tracony).
3. ↑#11 … ↑#18: B. ↑#19: zapis B (bit d10 tracony).
4. ↑#20 … ↑#27: bajt operacji. ↑#28: zapis (ALU dostaje `d9..d6`).
5. ↑#29: `STORE_RESULT` → wynik i flagi wpisane do `shift_out` → `READY`.
6. W następnej ramce `shift_out` wysuwa `{wynik, flagi, 16'b0}` od MSB.

## Mapowanie flag ALU na bity odpowiedzi

`s_flags[i]` trafia na bit `16+i` słowa MISO (patrz [protokol_spi.md §3](protokol_spi.md#miso-odpowiedź-wynik-poprzedniej-ramki)).

| Bit | Port ALU | Znaczenie |
|---|---|---|
| `s_flags[0]` | `o_SF` | `R[7]` |
| `s_flags[1]` | `o_OF` | `R == 0xFF` |
| `s_flags[2]` | `o_NF` | parzysta liczba jedynek w R |
| `s_flags[3]` | `o_BF` | R one-hot |

Szczegóły: [exe_unit_alu.md](exe_unit_alu.md#flagi).

## Drobiazgi

- Sygnał `result_enable` nie jest zadeklarowany (Yosys tworzy niejawny net i ostrzega). Jest ustawiany na `0` i nigdzie nie czytany.
- Skrypt syntezy tego modułu jako jedyny eksportuje hierarchię do `DOC/spi_exe_unit_1.json` (`prep` + `write_json`).

## Znane problemy

README: A2, A3, A5, A7, D1–D5. Najważniejsze:

- latche;
- brak resynchronizacji na CS;
- MISO nie jest trójstanowe;
- niepodłączone wejścia shifterów;
- na sztywno wpisane `{16{1'b0}}` i `s_cycles = 8`.
