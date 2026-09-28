# ALU (`exe_unit_rtl`, `exe_unit_rtl_2`)

Pliki:

- `MODEL/SPI_EXE_UNIT_1/exe_unit_1_rtl.sv`: moduł `exe_unit_rtl` (1417 linii)
- `MODEL/SPI_EXE_UNIT_2/exe_unit_rtl_2.sv`: moduł `exe_unit_rtl_2` (1121 linii)
- `MODEL/SPI_EXE_UNIT_3/exe_unit_rtl.sv`: moduł `exe_unit_rtl` (1121 linii)

Wszystkie trzy to **netlisty wygenerowane przez Yosysa**, każda inną wersją: 0.12+54, 0.10.0 i 0.13+15, co sugeruje trzech różnych autorów. Netlisty składają się z bramek `&`, `|`, `^`, `~`. W repozytorium nie ma źródeł behawioralnych. Układy są czysto **kombinacyjne**: 8-bitowe argumenty `i_argA` i `i_argB`, 4-bitowy `i_oper`, 8-bitowy `o_result` i 4 flagi.

## Metoda

Każdą netlistę zasymulowano (Icarus Verilog) dla **wszystkich 16 × 256 × 256 = 1 048 576 kombinacji** wejść i dopasowano funkcje. Każdy wiersz tabel poniżej zgadza się z netlistą w **100%** przypadków. Nazwy podmodułów netlist wskazują, z których ćwiczeń pochodzą bloki. Przypisanie podmodułu do opcode'u wynika z porównania zachowania z nazwą.

Oznaczenia:

- `A`, `B`: wejścia bez znaku 0..255, wynik zawsze modulo 256;
- `clmul(x, y)`: mnożenie bez przeniesień (wielomiany nad GF(2));
- „U2”: kod uzupełnień do dwóch, „ZM”: znak-moduł, „U1”: kod uzupełnień do jedności.

---

## Jednostka 1

Moduł `exe_unit_rtl` w `SPI_EXE_UNIT_1/exe_unit_1_rtl.sv`. Podmoduły: `crc_eval` (×2), `onehot2nkb_encoder`, `priority_encoder`, `sign_to_u2`, `u2tosign_module`, `zero_counter`.

| Opcode | Operacja | Szczegóły / przypadki brzegowe |
|---|---|---|
| 0 | `A − B` | modulo 256 |
| 1 | `A XOR B` | |
| 2 | `NAND`: `~(A & B)` | |
| 3 | `A << B` | `B ≥ 8` → 0 |
| 4 | `A >> B` (logiczne) | `B ≥ 8` → 0 |
| 5 | „CRC” (`crc_eval`, `i_crc=0`) | `clmul(A[2:0], B[2:0]) & 3'b111`. Zależy tylko od 3 najmłodszych bitów A i B. **To nie jest reszta z dzielenia wielomianów**, więc implementacja CRC jest wadliwa |
| 6 | „sprawdzenie CRC” (`crc_eval`, `i_crc=B[6:4]`) | `clmul(A[2:0], B[2:0])[2:0] XOR B[6:4]` |
| 7 | indeks najmłodszej jedynki A (`onehot2nkb_encoder`) | dla A one-hot to konwersja one-hot → NKB; `A=0` → 0 |
| 8 | liczba zer w `{A, B}` (`zero_counter`) | **modulo 16**: `A=B=0` daje 0 zamiast 16 (4-bitowe wyjście) |
| 9 | U2 → ZM (`u2tosign_module`) | `A ≥ 128`: `128 \| (−A)`; `A=128` → 128 („−0”) |
| 10 | ZM → U2 (`sign_to_u2`) | `A ≥ 128`: `−(A & 127)`; `A=128` („−0”) → 0 |
| 11 | indeks najstarszej jedynki A (`priority_encoder`) | `A=0` → **7** |
| 12–15 | — | wynik 0 |

## Jednostka 2

Moduł `exe_unit_rtl_2`. Podmoduły: `adder`, `crc_eval`, `n_to_onehot`, `sumzeros`, `thermometer_encoder`, `u2togray`, `zm_to_u2`.

| Opcode | Operacja | Szczegóły / przypadki brzegowe |
|---|---|---|
| 0 | `A + B` (`adder`) | modulo 256, VF = przeniesienie (`A+B > 255`) |
| 1 | `A XOR B` | |
| 2 | `XNOR`: `~(A ^ B)` | |
| 3 | `A >> 1` (logiczne) | |
| 4 | `A << 1` | |
| 5 | kod Graya: `A ^ (A >> 1)` (`u2togray`) | |
| 6 | ZM → U2 (`zm_to_u2`) | jak op 10 w jednostce 1 (`128` → 0) |
| 7 | „CRC” (`crc_eval`) | `clmul(A[2:0], B[2:0])[2:0]`, identycznie jak op 5 w jednostce 1 |
| 8 | liczba zer w `{A, B}` (`sumzeros`) | 0..16 (bez przepełnienia) |
| 9 | kod termometryczny (`thermometer_encoder`) | `A=1..8` → `(1<<A)−1` (A jedynek); **`A=0` → 0xFF** (powinno być 0); `A>8` → 0xFF i VF=1 |
| 10 | NKB → one-hot (`n_to_onehot`) | `A=1..8` → `1 << (A−1)`; `A=0` → 0; `A>8` → 0; VF=1 dla `A ≥ 8` (także dla poprawnego `A=8`) |
| 11–15 | — | wynik 0 |

## Jednostka 3

Moduł `exe_unit_rtl` w `SPI_EXE_UNIT_3/exe_unit_rtl.sv`. Podmoduły: `CRC4`, `OnehotTobinary`, `U1naU2`, `U2naGraya`, `binaryTothermometer`, `sprawdzenieZgodnosciCrc`, `zliczanie0`.

| Opcode | Operacja | Szczegóły / przypadki brzegowe |
|---|---|---|
| 0 | `A + B` | modulo 256 |
| 1 | `A OR B` | |
| 2 | `A >> 1` (logiczne) | |
| 3 | `NAND`: `~(A & B)` | |
| 4 | kod termometryczny (`binaryTothermometer`) | `A=0..7` → `(1<<(A+1))−1` (**A+1** jedynek); `A ≥ 7` → 0xFF |
| 5 | one-hot → NKB (`OnehotTobinary`) | A one-hot → indeks jedynki; A nie one-hot (także 0) → 0 |
| 6 | `A << 1` | |
| 7 | liczba zer w `{A, B}` (`zliczanie0`) | 0..16 |
| 8–11 | — | wynik 0 |
| 12 | „CRC4” (`CRC4`) | `clmul(A[3:0], B[3:0])[3:0]` |
| 13 | U2 → Gray (`U2naGraya`) | `A < 128` → `A ^ (A>>1)`; **A ujemne → 0** |
| 14 | „sprawdzenie CRC” (`sprawdzenieZgodnosciCrc`) | `clmul(A[2:0], B[5:3])[2:0] XOR B[2:0]` |
| 15 | U1 → U2 (`U1naU2`) | `A ≥ 128` → `A + 1`; `A=255` („−0”) → 0 |

---

## Flagi

Flagi są funkcją **wyniku** `R = o_result`, niezależnie od opcode'u. Wyjątkiem jest `VF` w jednostce 2. Nazwy portów często nie odpowiadają zachowaniu. Poniżej zachowanie zmierzone.

### Jednostka 1

| Bit w odpowiedzi | Port | Zachowanie |
|---|---|---|
| F0 (`o_data[16]`) | `o_SF` | `R[7]` (znak) |
| F1 (`o_data[17]`) | `o_OF` | `R == 8'hFF` (**nie** jest to przepełnienie) |
| F2 (`o_data[18]`) | `o_NF` | parzysta liczba jedynek w R (parzystość, `R=0` → 1) |
| F3 (`o_data[19]`) | `o_BF` | R ma dokładnie jedną jedynkę (one-hot) |

### Jednostka 2

| Bit | Port | Zachowanie |
|---|---|---|
| F0 | `o_VF` | op 0: przeniesienie z `A+B`; op 9: `A > 8`; op 10: `A ≥ 8`; pozostałe: 0 |
| F1 | `o_BF` | R one-hot |
| F2 | `o_SF` | `R[7]` |
| F3 | `o_OF` | `R == 8'hFF` |

### Jednostka 3

| Bit | Port | Zachowanie |
|---|---|---|
| F0 | `o_OF` | `R == 1` (**nie** jest to przepełnienie) |
| F1 | `o_SF` | `R[7]` |
| F2 | `o_ZF` | `R == 0` |
| F3 | `o_PF` | nieparzysta liczba jedynek w R |

Dla opcode'ów „pustych” (wynik 0) flagi i tak się ustawiają. Na przykład w jednostce 1 F2=1 (parzystość zera), a w jednostce 3 F2=ZF=1. Dlatego oczekiwana odpowiedź `28'b0000_0000_0100_0000…` pojawia się w wektorach tak często.

## Uwagi

- Moduł `exe_unit_rtl` występuje w dwóch plikach (jednostka 1 i 3), a `$paramod$0f84…\crc_eval` w jednostkach 1 i 2. Nie da się ich skompilować razem bez zmiany nazw. W pełnym flow nie przeszkadza to, bo każdy slave jest syntezowany osobno i spłaszczany (`flatten`).
- Moduły „CRC” liczą tylko obcięty iloczyn wielomianów, a nie resztę z dzielenia. Wyniki są deterministyczne i testowane, ale nie odpowiadają definicji CRC.
- Źródła behawioralne ALU należałoby dodać do repozytorium (README B6).
