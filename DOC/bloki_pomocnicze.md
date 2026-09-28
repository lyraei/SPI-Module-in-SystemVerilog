# Bloki pomocnicze: `shifter` i `watchdog`

Oba moduły występują w **dwóch kopiach**: w `MODEL/SPI_MASTER` i w `MODEL/SPI_EXE_UNIT_1`.

- Kopie `shifter.sv` są bajt w bajt identyczne.
- `watchdog.sv` w `SPI_MASTER` różni się jedną linią: blok sekwencyjny ma tam `always_ff`, a w kopii slave'a zwykłe `always`. Funkcjonalnie kopie są równoważne.

---

## `shifter`

Plik: `MODEL/*/shifter.sv` (47 linii). Rejestr przesuwny w lewo z wpisem równoległym.

### Parametry i porty

| Nazwa | Kier. | Szer. | Opis |
|---|---|---|---|
| `N` | param | — | Szerokość rejestru (domyślnie 4; używane 8 i 28) |
| `i_clk_p` | in | 1 | Zegar (zbocze narastające) |
| `i_rst_n` | in | 1 | Reset asynchroniczny, aktywny `0` → rejestr = 0 |
| `i_bit` | in | 1 | Wejście szeregowe (wsuwane na LSB) |
| `i_data` | in | N | Wejście równoległe |
| `i_en` | in | 1 | Zezwolenie na jakąkolwiek zmianę |
| `i_wrt` | in | 1 | `1` = wpis równoległy, `0` = przesunięcie |
| `o_data` | out | N | Zawartość rejestru |
| `o_bit` | out | 1 | Wyjście szeregowe = `s_shifter[N-1]` (MSB) |

### Działanie

| `i_en` | `i_wrt` | Następna wartość |
|---|---|---|
| 0 | x | bez zmian |
| 1 | 1 | `i_data` |
| 1 | 0 | `{s_shifter[N-2:0], i_bit}` (przesunięcie w lewo) |

W kodzie przesunięcie jest zapisane jako `{s_shifter, i_bit}`, czyli wyrażenie N+1-bitowe, które przypisanie obcina do N bitów (MSB wypada). Działa to poprawnie, ale linter zgłosi niejawne obcięcie.

Budowa: blok kombinacyjny `always @(*)` liczy `s_shifter_next`, `o_data` i `o_bit`, a blok `always @(posedge i_clk_p, negedge i_rst_n)` przechowuje stan.

### Użycie w projekcie

| Gdzie | N | Zegar | Rola |
|---|---|---|---|
| master `shift` | 28 | ↑ SCLK | nadawanie (MSB → MOSI) i odbiór (MISO → LSB) jednocześnie |
| slave `shift_in` | 8 | ↑ SCLK | odbiór 8-bitowych pól z MOSI; `i_data` niepodłączone |
| slave `shift_out` | 28 | ↑ SCLK | nadawanie `{wynik, flagi, 16'b0}` na MISO; `i_bit` niepodłączone |

---

## `watchdog`

Plik: `MODEL/*/watchdog.sv` (66 linii). Mimo nazwy nie jest to watchdog, tylko **przeładowywany licznik w dół**, który co zadaną liczbę taktów generuje impuls `o_inter`. W projekcie służy jako licznik bitów pola lub ramki.

### Parametry i porty

| Nazwa | Kier. | Szer. | Opis |
|---|---|---|---|
| `N` | param | — | Szerokość licznika (domyślnie 4; używane 4 i 6) |
| `i_clk_p` | in | 1 | Zegar (zbocze narastające) |
| `i_rst_n` | in | 1 | Reset asynchroniczny, aktywny `0` → `s_count = s_cycles = 0` |
| `i_cycles` | in | N | Wartość początkowa |
| `i_we` | in | 1 | Wpis `i_cycles` do licznika i do rejestru okresu |
| `o_inter` | out | 1 | Impuls „licznik doszedł do zera” (kombinacyjny) |

### Rejestry

- `s_count`: bieżąca wartość licznika.
- `s_cycles`: zapamiętany okres, używany do automatycznego przeładowania.

### Działanie (na każde ↑ `i_clk_p`)

| Warunek | `s_count` ← | `s_cycles` ← | `o_inter` (przed zboczem) |
|---|---|---|---|
| `i_we = 1` | `i_cycles` | `i_cycles` | 0 |
| `i_we = 0`, `s_count > 0` | `s_count − 1` | bez zmian | 0 |
| `i_we = 0`, `s_count = 0` | `s_cycles` (przeładowanie) | bez zmian | **1** |
| `s_cycles = 0` | (jak wyżej) | | wymuszone **0**, czyli licznik „wyłączony” |

`o_inter` jest kombinacyjne: ma wartość `1` przez cały takt, w którym `s_count == 0` (i `s_cycles ≠ 0`, `i_we = 0`). Układ, który go używa, reaguje na najbliższym zboczu.

### Okres: uwaga na off-by-one

Po wpisie wartości `K` licznik przechodzi przez `K, K−1, …, 1, 0`, a następnie przeładowuje się do `K`. Okres wynosi więc **K+1 zboczy**:

```
zbocze:    we    +1    +2   ...   +K   +K+1  +K+2
s_count:   K     K-1   K-2  ...   0     K     K-1
o_inter:   0     0     0    ...   1     0     0
                                  └─ reakcja FSM na zboczu +K+1
```

- **Slave** ładuje `K=8`, więc co 9 zboczy wczytuje 8-bitowe pole. Stąd martwe bity 19 i 10 w ramce.
- **Master** ładuje `K=28`, więc generuje 29 zboczy SCLK.

Szczegóły: [protokol_picore.md §4](protokol_picore.md#4-przebieg-jednej-ramki-zbocze-po-zboczu).

### Użycie w projekcie

| Gdzie | N | `i_cycles` | Rola |
|---|---|---|---|
| master `watchdog` | 6 (`$clog2(28)+1`) | 28 (stała 32-bitowa obcinana do 6 bitów, ostrzeżenie Yosysa) | koniec ramki |
| slave `counter` | 4 | 8 (w `READY`), 0 poza nim, ale `i_we=0`, więc bez znaczenia | koniec każdego 8-bitowego pola |
