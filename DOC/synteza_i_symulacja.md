# Synteza i symulacja

## Flow

```
MODEL/SPI_MASTER/*.sv    ──┐                         RTL/spi_master_rtl.sv
                           ├─► Yosys (WORK/*.ys) ──►
MODEL/SPI_EXE_UNIT_1/*.sv──┘                         RTL/spi_exe_unit_1_rtl.sv
                                                               │
                                                               ▼
                         TEST/testbench.sv + TEST/*.vh ──► Icarus Verilog ──► wynik + WORK/waves.vcd
```

Symulowane są **netlisty po syntezie**, a nie modele. Testbench instancjonuje moduły `*_rtl`.

## Wymagane narzędzia

| Narzędzie | Do czego | Sprawdzone wersje |
|---|---|---|
| Yosys | synteza (`make rtl`) | 0.69 (netlista ALU pochodzi z 0.12+54) |
| Icarus Verilog | symulacja (`make sim`) | 12.0 (flaga `-g2005-sv` wystarcza) |
| GTKWave | podgląd przebiegów (`make wave`) | opcjonalnie |
| bash | Makefile używa `\|&` | `SHELL := /bin/bash` |

---

## Makefile

Plik: `WORK/makefile`. Wszystkie cele uruchamia się z katalogu `WORK/`.

| Cel | Polecenia | Opis |
|---|---|---|
| `rtl` | `yosys -s spi_master.ys`, `yosys -s spi_slave_1.ys` | Synteza mastera i slave'a. Log każdego trafia do `WORK/<nazwa>.yosys.log` (`\|& tee`) |
| `sim` | `iverilog -g2005-sv ../RTL/*.sv ../TEST/testbench.sv -o spi_test.iveri.run`, potem `./spi_test.iveri.run` | Kompilacja i uruchomienie symulacji. Zależy od `clear` |
| `clear` | usuwa `spi_test.iveri.run` | Sprzątanie przed kompilacją |
| `wave` | `gtkwave waves.vcd &` | Podgląd przebiegów |

Zmienne: `SYNTH = yosys`, `RTL_FILES = ../RTL/*.sv`, `TB_FILES = ../TEST/testbench.sv`.

Uwagi:

- `sim` **nie zależy od** `rtl`. Na świeżym klonie trzeba najpierw wykonać `make rtl`.
- `spi_slave_1.ys` zapisuje `../DOC/spi_exe_unit_1.json`, więc do syntezy potrzebny jest katalog `DOC/`.
- `sim` kompiluje wszystko z `RTL/*.sv`. Stare netlisty `spi_exe_unit_2_rtl.sv`/`_3_rtl.sv` z wcześniejszej wersji projektu nie przeszkadzają, ale warto je usunąć.

---

## Skrypty Yosysa (`*.ys`)

Pliki: `WORK/spi_master.ys` i `WORK/spi_slave_1.ys`. Oba mają tę samą strukturę:

| Krok | Polecenie | Co robi |
|---|---|---|
| 1 | `read_verilog -sv ../MODEL/<KATALOG>/*.sv` | Wczytuje pliki modułu (master wymienia je osobno, slave przez `*.sv`, łącznie z netlistą ALU) |
| 1a | `prep -top spi_exe_unit_1` + `write_json ../DOC/spi_exe_unit_1.json` | **Tylko slave.** Eksport hierarchii do JSON (np. dla netlistsvg) |
| 2 | `synth` | Generyczna synteza (bez `-top`, Yosys wybiera top sam) |
| 3 | `abc -g AND,OR,XOR` | Mapowanie logiki kombinacyjnej na bramki AND/OR/XOR (+ NOT) |
| 4 | `opt_clean` | Usunięcie nieużywanych przewodów |
| 5 | `flatten` | Spłaszczenie hierarchii (shifter, watchdog i ALU trafiają do jednego modułu) |
| 6 | `copy X X_rtl`, `select *`, `select -del X_rtl`, `delete`, `select *` | „Zmiana nazwy” topu na `X_rtl` i usunięcie pozostałych modułów |
| 7 | `write_verilog -noattr ../RTL/X_rtl.sv` | Zapis netlisty bez atrybutów |

Wynik: w `RTL/` powstają `spi_master_rtl.sv` i `spi_exe_unit_1_rtl.sv`. Logika kombinacyjna jest zapisana jako `assign` z operatorami `&`, `|`, `^`, `~`, a przerzutniki jako bloki `always @(posedge …, negedge i_rst)`. Latche slave'a (komórki `$_DLATCH_`) są zapisane jako `always @*` z warunkiem `if`.

Ostrzeżenia zgłaszane podczas syntezy (stan obecny):

- `spi_master`: `Resizing cell port spi_master.watchdog.i_cycles from 32 bits to 6 bits`.
- `spi_exe_unit_1`:
  - `Identifier '\result_enable' is implicitly declared`;
  - 5 × `Latch inferred` (`s_result`, `s_flags`, `s_argA_next`, `s_argB_next`, `s_oper_next`).

---

## Testbench

Plik: `TEST/testbench.sv` (128 linii), moduł `testbench`.

### Ustawienia

| Makro | Wartość | Znaczenie |
|---|---|---|
| `` `timescale `` | `1s/1ms` | jednostka 1 s, więc okres zegara wynosi 20 s (wartości symboliczne, bez znaczenia fizycznego) |
| `CLKSTEP` | 10 | półokres zegara |
| `RSTTIME` | 201 | czas trwania resetu |
| `SIMTIME`, `DATASTEP` | 28000, 250 | zdefiniowane, **nieużywane** |
| `BITS` (param) | 28 | szerokość ramki |

### Układ testowany

- `spi_master_rtl spi_master`: master (`clk`, `rst`, `send_data`, `send_request`, `received_data`, `master_busy`).
- `spi_exe_unit_1_rtl spi_exe_unit_1`: slave, połączony bezpośrednio liniami `spi_sclk`, `spi_mosi`, `spi_miso` i `spi_ss`.

### Sterowanie (handshake)

```
always @(posedge clk)                        always @(negedge clk)
  if rst & !master_busy:                       if rst & !master_busy & !send_request:
     if !send_request: -> next_data               -> check_data
     send_request = 1                             porównaj received_data z expected_data
  else if busy: send_request = 0                  (błąd → $display + licznik)
```

Kolejność w czasie dla jednego wektora:

1. Plik `.vh` ustawia `send_data` i `expected_data`, a następnie czeka na `@(next_data)`.
2. Gdy master jest wolny, na ↑`clk` wyzwalane jest `next_data` i podnoszony `send_request`, a master startuje ramkę.
3. W trakcie ramki (`busy=1`) `send_request` wraca do 0.
4. Po ramce, na ↓`clk` (busy=0, send_request=0), `received_data` jest porównywane z `expected_data` **tego samego** wektora.
5. Na kolejnym ↑`clk` `next_data` budzi blok `initial`, który wystawia kolejny wektor.

Porównanie w kroku 4 dotyczy odpowiedzi MISO, czyli wyniku operacji z **poprzedniej** ramki. Dlatego w pliku `.vh` `expected_data[k]` = wynik dla `send_data[k−1]` (patrz [protokol_spi.md §5](protokol_spi.md#5-potok-wynik-przychodzi-w-następnej-ramce)).

### Przebieg testu

1. Reset do `t = 201`.
2. `` `include "../TEST/test_spi_exe_unit_1.vh" ``.
3. `-> end_simulation`: wypisanie liczby błędnych i poprawnych transferów, a potem `$finish`.
4. Przez cały czas `$dumpvars(0, testbench)` zapisuje przebiegi do `waves.vcd`.

Komunikat błędu: `ERROR @<czas>s: Bledny transfer: received_data=…, expected_data=…`. Format `%21b` jest za krótki dla 28 bitów, ale Icarus i tak wypisuje pełną wartość.

Wynik: **553 poprawne, 0 błędnych transferów**.

---

## Wektory testowe (`*.vh`)

Plik `TEST/test_spi_exe_unit_1.vh` (2212 linii, 553 wektory) to fragment kodu proceduralnego wklejany przez `` `include `` do bloku `initial` testbencha. Zaczyna się od `send_request = 1;`, a potem następują powtarzane trójki:

```verilog
send_data = 28'bAAAAAAAA0BBBBBBBB0PPPP000000;
expected_data = 28'bRRRRRRRRFFFF0000000000000000;
@(next_data);
```

Każdy transfer jest sprawdzany dokładnie raz.

- Pierwszy wektor oczekuje `'0`, czyli stanu po resecie.
- Każdy kolejny oczekuje wyniku ALU dla poprzedniego wektora (zgodność 552/552, sprawdzona bezpośrednio na netliście ALU).
