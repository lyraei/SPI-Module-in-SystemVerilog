# `spi_master`: master SPI

Plik: `MODEL/SPI_MASTER/spi_master.sv` (152 linie). Używa modułów `shifter` i `watchdog` z tego samego katalogu.

## Parametry

| Parametr | Domyślnie | Opis |
|---|---|---|
| `BITS` | 28 | Długość ramki (szerokość `i_data`/`o_data`, rejestru przesuwnego i zakresu licznika) |
| `SLAVES_NUMBER` | 3 | **Nieużywany.** Master ma jedno wyjście `o_ss` |

## Porty

| Port | Kier. | Szer. | Opis |
|---|---|---|---|
| `i_clk` | in | 1 | Zegar systemowy. Taktuje tylko rejestr stanu FSM |
| `i_rst` | in | 1 | Reset asynchroniczny, aktywny `0` |
| `i_data` | in | `BITS` | Słowo do wysłania |
| `i_send` | in | 1 | Start transmisji (sprawdzany w `READY`) |
| `o_data` | out | `BITS` | Zawartość rejestru przesuwnego (odebrane słowo po zakończeniu) |
| `o_busy` | out | 1 | Transmisja w toku |
| `i_miso` | in | 1 | Linia MISO |
| `o_mosi` | out | 1 | Linia MOSI (rejestr) |
| `o_sclk` | out | 1 | Linia SCLK (kombinacyjnie ze stanu) |
| `o_ss` | out | 1 | Linia SS, aktywna `0` (kombinacyjnie ze stanu) |

## Struktura wewnętrzna

```
             i_clk
               │
        ┌──────▼──────┐  s_state  ┌───────────────────────┐
i_send ─►  rejestr    ├──────────►│ logika kombinacyjna   ├─► o_sclk ─┬─► (wyjście)
        │  stanu FSM  │◄──────────┤ (always @(*))         ├─► o_ss    │
        └─────────────┘ s_state_  │                       ├─► o_busy  │
                        next      │                       ├─► s_sout_en, s_sout_wrt
                                  │                       ├─► s_watchdog_we
                        s_inter ─►│                       │
                                  └───────────────────────┘
```

Ścieżka danych (wszystko taktowane przez `o_sclk`):

```
                 i_data[27:0]
                      │
                      ▼
 i_miso ──►[s_bit_in]──► i_bit ┌──────────────────┐ o_bit (MSB)
           (↑ sclk)            │ shifter #(28)    ├──────────►[o_mosi]──► o_mosi
                               │ (↑ sclk)         │             (↓ sclk)
                               └────────┬─────────┘
                                        └──► o_data[27:0]

                  BITS=28 ──► ┌──────────────────┐
                              │ watchdog #(6)    ├──► s_inter ──► FSM
                              │ (↑ sclk)         │
                              └──────────────────┘
```

### Instancje

| Instancja | Moduł | Zegar | Połączenia |
|---|---|---|---|
| `shift` | `shifter #(.N(BITS))` | ↑ `o_sclk` | `i_data`: słowo użytkownika; `i_bit`: `s_bit_in`; `i_en`: `s_sout_en`; `i_wrt`: `s_sout_wrt`; `o_data`: `o_data`; `o_bit`: `s_bit` |
| `watchdog` | `watchdog #(.N($clog2(BITS)+1))` (6 bitów) | ↑ `o_sclk` | `i_cycles`: `BITS`; `i_we`: `s_watchdog_we`; `o_inter`: `s_inter` |

### Rejestry poza instancjami

| Rejestr | Zegar | Funkcja |
|---|---|---|
| `s_state` | ↑ `i_clk` | stan FSM |
| `o_mosi` | ↓ `o_sclk` | `o_mosi <= s_bit` (MSB rejestru przesuwnego) |
| `s_bit_in` | ↑ `o_sclk` | `s_bit_in <= i_miso`. Dodatkowy rejestr opóźniający wejście o jedno zbocze (komentarz w kodzie: „w celu opóźnienia wejścia o jeden takt”) |

Master ma więc **dwie domeny zegarowe**: FSM na `i_clk` oraz ścieżkę danych na `o_sclk`, który jest wyjściem kombinacyjnym FSM.

## Maszyna stanów

Kodowanie: 3 bity (`$clog2(6)`), wartości w nawiasach.

```
             i_send
  ┌────────┐ ─────► ┌──────┐      ┌──────┐      ┌──────┐ ◄───── ┌──────┐
  │READY(0)│        │SS (5)├─────►│LOAD 1├─────►│LOW  3│        │HIGH 2│
  └────────┘ ◄──┐   └──────┘      └──────┘      └──┬───┘ ─────► └──────┘
       ▲        │                                  │ s_inter
       │     ┌──┴───┐                              │
       └─────┤END 4 │◄─────────────────────────────┘
             └──────┘
```

| Stan | Następny | `o_ss` | `o_sclk` | `o_busy` | `sout_en` | `sout_wrt` | `watchdog_we` |
|---|---|---|---|---|---|---|---|
| `READY` | `SS` gdy `i_send`, inaczej `READY` | 1 | 0 | 0 | 0 | 0 | 0 |
| `SS` | `LOAD` | 0 | 0 | 1 | 1 | 1 | 1 |
| `LOAD` | `LOW` | 0 | **1** | 1 | 1 | 1 | 1 |
| `LOW` | `END` gdy `s_inter`, inaczej `HIGH` | 0 | 0 | 1 | 1 | 0 | 0 |
| `HIGH` | `LOW` | 0 | **1** | 1 | 1 | 0 | 0 |
| `END` | `READY` | 1 | 0 | 1 | 0 | 0 | 0 |
| inne | `READY` | 1 | 0 | 0 | 0 | 0 | 0 |

Uwagi:

- Wpis równoległy (`sout_wrt`) i ładowanie licznika (`watchdog_we`) mają skutek tylko w `LOAD`, bo tylko wtedy pojawia się zbocze ↑ SCLK. Ustawienie ich w `SS` nic nie robi.
- `s_sin_en` i `s_sin_wrt` są zadeklarowane i zerowane, ale nigdzie nie używane (pozostałość po osobnym rejestrze wejściowym).
- Licznik jest ładowany wartością 28 na ↑#1 (`LOAD`) i dekrementowany na ↑#2 … ↑#29, więc `s_inter=1` pojawia się po ↑#29. Stąd 29 impulsów SCLK na ramkę (szczegóły: [protokol_spi.md §4](protokol_spi.md#4-przebieg-jednej-ramki-zbocze-po-zboczu)).

## Ścieżka nadawcza (MOSI)

1. ↑#1 (`LOAD`): `shift.s_shifter ← i_data`.
2. ↓#1: `o_mosi ← s_shifter[27]` (bit `d27`).
3. ↑#k (k ≥ 2): rejestr przesuwa się w lewo o 1 (`{s_shifter, s_bit_in}`), a na ↓#k MOSI dostaje kolejny bit.

## Ścieżka odbiorcza (MISO)

1. ↑#k: `s_bit_in ← i_miso` (wartość sprzed zbocza).
2. ↑#k+1: `s_bit_in` wsuwane na LSB rejestru przesuwnego.
3. Po ↑#29 rejestr zawiera MISO z ↑#1 … ↑#28, gdzie bit z ↑#1 ląduje na pozycji 27.

`o_data` to bezpośrednio `s_shifter`. W trakcie transmisji jest mieszanką wysyłanego i odbieranego słowa, a ważne jest dopiero po `o_busy=0`.

## Znane problemy

Szczegóły w README: A1, A4, A5, A6, E2–E5. Najważniejsze:

- SCLK i SS są kombinacyjne i SCLK taktuje przerzutniki (zegar generowany z logiki).
- Parametr `SLAVES_NUMBER` jest martwy, a SS tylko jeden.
- Yosys ostrzega o dopasowaniu 32-bitowej stałej `BITS` do 6-bitowego portu `i_cycles`.
