# Synteza i symulacja

## Flow

```
MODEL/SPI_MASTER/*.sv  ──┐
MODEL/SPI_EXE_UNIT_1/*.sv┼─► Yosys (WORK/*.ys) ──► RTL/spi_master_rtl.sv
MODEL/SPI_EXE_UNIT_2/*.sv│                         RTL/spi_exe_unit_{1,2,3}_rtl.sv
MODEL/SPI_EXE_UNIT_3/*.sv┘                                 │
                                                           ▼
                        TEST/testbench.sv + TEST/*.vh ──► Icarus Verilog ──► wynik + WORK/waves.vcd
```

Symulowane są **netlisty po syntezie**, a nie modele. Testbench instancjonuje moduły `*_rtl`.

## Wymagane narzędzia

| Narzędzie | Do czego | Sprawdzone wersje |
|---|---|---|
| Yosys | synteza (`make rtl`) | 0.69 (w projekcie netlisty ALU pochodzą z 0.10–0.13) |
| Icarus Verilog | symulacja (`make sim`) | 12.0 (flaga `-g2005-sv` wystarcza) |
| GTKWave | podgląd przebiegów (`make wave`) | opcjonalnie |
| bash | Makefile używa `\|&` | `SHELL := /bin/bash` |

---

## Makefile

Plik: `WORK/makefile`. Wszystkie cele uruchamia się z katalogu `WORK/`.

| Cel | Polecenia | Opis |
|---|---|---|
| `rtl` | `yosys -s spi_master.ys`, `spi_slave_1.ys`, `_2`, `_3` | Synteza 4 modułów. Log każdego trafia do `WORK/<nazwa>.yosys.log` (`\|& tee`) |
| `sim` | `iverilog -g2005-sv ../RTL/*.sv ../TEST/testbench.sv -o spi_test.iveri.run`, potem `./spi_test.iveri.run` | Kompilacja i uruchomienie symulacji. Zależy od `clear` |
| `clear` | usuwa `spi_test.iveri.run` | Sprzątanie przed kompilacją |
| `wave` | `gtkwave waves.vcd &` | Podgląd przebiegów |

Zmienne: `SYNTH = yosys`, `RTL_FILES = ../RTL/*.sv`, `TB_FILES = ../TEST/testbench.sv`.

Uwagi:

- `sim` **nie zależy od** `rtl`. Na świeżym klonie trzeba najpierw wykonać `make rtl`.
- `spi_slave_1.ys` zapisuje `../DOC/spi_exe_unit_1.json`, więc do syntezy potrzebny jest katalog `DOC/` (istnieje od dodania tej dokumentacji).

---

## Skrypty Yosysa (`*.ys`)

Pliki: `WORK/spi_master.ys`, `WORK/spi_slave_1.ys`, `WORK/spi_slave_2.ys`, `WORK/spi_slave_3.ys`. Wszystkie mają tę samą strukturę:

| Krok | Polecenie | Co robi |
|---|---|---|
| 1 | `read_verilog -sv ../MODEL/<KATALOG>/*.sv` | Wczytuje wszystkie pliki modułu (master wymienia je osobno, slave'y przez `*.sv`, łącznie z netlistą ALU) |
| 1a | `prep -top spi_exe_unit_1` + `write_json ../DOC/spi_exe_unit_1.json` | **Tylko slave 1.** Eksport hierarchii do JSON (np. dla netlistsvg) |
| 2 | `synth` | Generyczna synteza (bez `-top`, Yosys wybiera top sam) |
| 3 | `abc -g AND,OR,XOR` | Mapowanie logiki kombinacyjnej na bramki AND/OR/XOR (+ NOT) |
| 4 | `opt_clean` | Usunięcie nieużywanych przewodów |
| 5 | `flatten` | Spłaszczenie hierarchii (shifter, watchdog i ALU trafiają do jednego modułu) |
| 6 | `copy X X_rtl`, `select *`, `select -del X_rtl`, `delete`, `select *` | „Zmiana nazwy” topu na `X_rtl` i usunięcie pozostałych modułów |
| 7 | `write_verilog -noattr ../RTL/X_rtl.sv` | Zapis netlisty bez atrybutów |

Wynik: w `RTL/` powstają `spi_master_rtl.sv` i `spi_exe_unit_{1,2,3}_rtl.sv`. Logika kombinacyjna jest zapisana jako `assign` z operatorami `&`, `|`, `^`, `~`, a przerzutniki jako bloki `always @(posedge …, negedge i_rst)`. Latche slave'ów (komórki `$_DLATCH_`) są zapisane jako `always @*` z warunkiem `if`.

Ostrzeżenia zgłaszane podczas syntezy (stan obecny):

- `spi_master`: `Resizing cell port spi_master.watchdog.i_cycles from 32 bits to 6 bits`.
- `spi_exe_unit_1`: `Identifier '\result_enable' is implicitly declared`.
- Każdy slave: 5 × `Latch inferred` (`s_result`, `s_flags`, `s_argA_next`, `s_argB_next`, `s_oper_next`).

---

## Testbench

Plik: `TEST/testbench.sv` (161 linii), moduł `testbench`.

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
- `spi_exe_unit_{1,2,3}_rtl`: trzy slave'y. Wszystkie dostają te same `spi_sclk`, `spi_mosi` i `spi_ss`, a każdy ma własne wyjście `s_miso[i]`.
- Multiplekser `always @(*) case(select_slave)` wybiera `spi_miso = s_miso[select_slave]`.

### Sterowanie (handshake)

```
always @(posedge clk)                        always @(negedge clk)
  if rst & !master_busy:                       if rst & !master_busy & !send_request:
     if !send_request: -> next_data               -> check_data
     send_request = 1                             porównaj received_data z expected_data
  else if busy: send_request = 0                  (błąd → $display + licznik)
```

Kolejność w czasie dla jednego wektora:

1. Pliki `.vh` ustawiają `send_data` i `expected_data`, a następnie czekają na `@(next_data)`.
2. Gdy master jest wolny, na ↑`clk` wyzwalane jest `next_data` i podnoszony `send_request`, a master startuje ramkę.
3. W trakcie ramki (`busy=1`) `send_request` wraca do 0.
4. Po ramce, na ↓`clk` (busy=0, send_request=0), `received_data` jest porównywane z `expected_data` **tego samego** wektora.
5. Na kolejnym ↑`clk` `next_data` budzi blok `initial`, który wystawia kolejny wektor.

Porównanie w kroku 4 dotyczy odpowiedzi MISO, czyli wyniku operacji z **poprzedniej** ramki. Dlatego w plikach `.vh` `expected_data[k]` = wynik dla `send_data[k−1]` (patrz [protokol_spi.md §5](protokol_spi.md#5-potok-wynik-przychodzi-w-następnej-ramce)).

### Przebieg testu

1. Reset do `t = 201`.
2. `` `include "../TEST/test_spi_exe_unit_1.vh" `` → `_2.vh` → `_3.vh`. Każdy plik na początku ustawia `select_slave`.
3. `-> end_simulation`: wypisanie liczby błędnych i poprawnych transferów, a potem `$finish`.
4. Przez cały czas `$dumpvars(0, testbench)` zapisuje przebiegi do `waves.vcd`.

Komunikat błędu: `ERROR @<czas>s: Bledny transfer: slave_number=…, received_data=…, expected_data=…`. Format `%21b` jest za krótki dla 28 bitów, ale Icarus i tak wypisuje pełną wartość.

---

## Wektory testowe (`*.vh`)

Pliki `TEST/test_spi_exe_unit_{1,2,3}.vh` to fragmenty kodu proceduralnego wklejane przez `` `include `` do bloku `initial` testbencha. Każdy zaczyna się od:

```verilog
select_slave = <0|1|2>;
send_request = 1;
```

Potem następują powtarzane trójki:

```verilog
send_data = 28'bAAAAAAAA0BBBBBBBB0PPPP000000;
expected_data = 28'bRRRRRRRRFFFF0000000000000000;
@(next_data);
```

| Plik | `select_slave` | Liczba wektorów | Linie |
|---|---|---|---|
| `test_spi_exe_unit_1.vh` | 0 | 553 | 2213 |
| `test_spi_exe_unit_2.vh` | 1 | 2000 | 8002 |
| `test_spi_exe_unit_3.vh` | 2 | 58 | 233 |

W sumie 2611 transferów, a każdy jest sprawdzany dokładnie raz.

### Znany błąd wektora

Pierwszy wektor `test_spi_exe_unit_3.vh` oczekuje `28'b0000000001000000000000000000`, czyli wyniku 0 i ZF=1. Faktycznie slave 3 zwraca `0010111110000…`: wynik ALU 3 dla **ostatniego wektora z pliku jednostki 2**, bo wszystkie slave'y słyszą każdą ramkę. To jedyny błędny transfer w symulacji (2610/2611). Oczekiwania dla wektorów 2..58 pliku jednostki 3 zgadzają się z netlistą ALU w 100%, podobnie wszystkie wektory jednostek 1 i 2 (jednostka 2 poprawnie przewiduje wynik z ostatniej ramki jednostki 1).

---

## `testbench_do_pliku_txt.sv`

Plik: `TEST/testbench_do_pliku_txt.sv` (95 linii). Pozostałość po ćwiczeniu z ALU, prawdopodobnie jednostki 2 (sądząc po flagach OF/SF/BF/VF). **Nie kompiluje się**, bo instancjonuje nieistniejący moduł behawioralny `exe_unit`.

Zamysł: porównywać model behawioralny `exe_unit` z netlistą `exe_unit_rtl` dla 2000 losowych par argumentów (`LICZBA_LOSOWAN`), z kolejnymi opcode'ami `s_oper = 0, 1, 2, …` (zawijanie modulo 16). Wynik miał być drukowany w formacie `send_data = …; expected_data = …; @(next_data);`, czyli jako gotowe linie pliku `.vh`.

Stan faktyczny:

- Warunek jest odwrócony: linia jest drukowana, gdy wyniki modelu i netlisty są **zgodne** (i `s_oper < 11`), a mimo to liczy się to jako „błąd”.
- Drukowane `expected_data` to 12-bitowy literał (bez 16 zer wypełnienia i bez przesunięcia o ramkę), więc obecne pliki `.vh` powstały inną wersją tego skryptu lub były obrabiane dalej.
- Liczniki flag nigdy się nie zmieniają, a `s_flags_*` mają szerokość 8 zamiast 4 bitów.
- Plik dumpuje do `signals.vcd`.
