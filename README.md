# PiCoRe — a pipelined command/response serial link

**PiCoRe** (*Pipelined Command/Response*) to synchroniczny, 4-przewodowy, full-duplex interfejs szeregowy z ramką stałej długości, napisany w SystemVerilogu. Master wysyła polecenie, a odpowiedź na nie przychodzi w **następnej** ramce, czyli z opóźnieniem jednej ramki (stąd *pipelined*). Linie nazywają się jak w SPI (SCLK, MOSI, MISO, SS), ale PiCoRe **nie jest zgodny ze standardem SPI**: ma inny timing, własny format ramki i semantykę komenda–odpowiedź.

Po drugiej stronie łącza siedzi jednostka wykonawcza (ALU, `exe_unit`). Slave przyjmuje w ramce dwa argumenty i kod operacji, a wynik z flagami odsyła w **następnej** ramce. Moduły opisane są w SystemVerilogu, syntezowane Yosysem do netlisty bramek AND/OR/XOR, a netlisty symulowane są w Icarus Verilog.

Pierwotnie projekt miał trzy slave'y z trzema różnymi ALU (od trzech autorów). Zostawiona jest tylko **jednostka 1**, a jednostki 2 i 3 zostały usunięte.

Pliki, katalogi i skrypty noszą już nazwy PiCoRe. Treść HDL pozostała bez zmian, więc po staremu nazywają się jeszcze:
- moduły `spi_master` i `spi_exe_unit_1` (oraz ich netlisty `spi_master_rtl` i `spi_exe_unit_1_rtl`);
- sygnały `spi_*` w testbenchu;
- plik wektorów `TEST/test_spi_exe_unit_1.vh`, bo jego ścieżka jest wpisana w `testbench.sv`.

Ich przemianowanie jest opisane w [roadmapie](DOC/roadmap.md), etap 0.

**Pełna dokumentacja: [`DOC/`](DOC/README.md)**. Zawiera:
- opis każdego pliku;
- działanie interfejsu PiCoRe zbocze po zboczu;
- tabelę operacji i flag ALU;
- [opis dziwactw projektu](DOC/dziwactwa.md);
- [plany rozwoju](DOC/roadmap.md).

## Struktura

| Ścieżka | Zawartość |
|---|---|
| `MODEL/PICORE_MASTER/picore_master.sv` | Master PiCoRe: FSM `READY→SS→LOAD→LOW⇄HIGH→END`, SCLK = `i_clk`/2, ramka 28 bitów, MSB first |
| `MODEL/PICORE_SLAVE/picore_slave.sv` | Slave: FSM `READY→LOAD_A→LOAD_B→LOAD_OPER→STORE_RESULT` + ALU |
| `MODEL/PICORE_SLAVE/exe_unit_1_rtl.sv` | Gotowa netlista ALU wygenerowana przez Yosysa (bez źródeł behawioralnych) |
| `MODEL/*/shifter.sv` | Rejestr przesuwny z wpisem równoległym (2 identyczne kopie) |
| `MODEL/*/watchdog.sv` | Przeładowywany licznik w dół z wyjściem `o_inter` (2 kopie) |
| `WORK/*.ys`, `WORK/makefile` | Skrypty syntezy Yosysa i Makefile (`rtl`, `sim`, `wave`) |
| `TEST/testbench.sv` | Testbench netlist: master + slave |
| `TEST/test_spi_exe_unit_1.vh` | Wektory testowe (553 transfery) |

### Format ramki (MOSI)

```
bit: 27      20 19 18      11 10 9  6 5    0
     AAAAAAAA   0  BBBBBBBB   0  PPPP 000000
```

Bity 19 i 10 to „martwe” separatory. Powstały przez off-by-one w `watchdog` (patrz A3).

### Format odpowiedzi (MISO, ramka k+1)

```
{ result[7:0], flags[3:0], 16'b0 }
```

Flagi `[0]`…`[3]`:

| Bit | Port | Znaczenie |
|---|---|---|
| `[0]` | SF | znak, `R[7]` |
| `[1]` | OF | `R == 0xFF` |
| `[2]` | NF | parzysta liczba jedynek |
| `[3]` | BF | R ma dokładnie jedną jedynkę |

## Uruchomienie

```bash
mkdir -p RTL            # na wypadek, gdyby checkout pominął pusty katalog
cd WORK
make rtl                # synteza Yosysem -> ../RTL/*_rtl.sv
make sim                # iverilog + uruchomienie
make wave               # gtkwave waves.vcd
```

Wymagane narzędzia: `yosys`, `iverilog` (sprawdzone na wersji 12), opcjonalnie `gtkwave`.

**Jeśli w lokalnym klonie `RTL/` zawiera pliki `spi_*_rtl.sv` z poprzedniej wersji projektu, usuń je** (`rm RTL/spi_*`). `make sim` kompiluje `RTL/*.sv`, a stare `spi_master_rtl.sv`/`spi_exe_unit_1_rtl.sv` definiują te same moduły co nowe `picore_*_rtl.sv`, więc Icarus zgłosi redeklarację.

## Stan weryfikacji (sprawdzone)

- Synteza obu skryptów przechodzi, **pod warunkiem że istnieje `DOC/`**.
- Yosys zgłasza **5 latchy** w slave'ie i niejawną deklarację `result_enable`.
- Symulacja kończy się wynikiem **553 poprawne, 0 błędnych transferów**.
- Każda wartość oczekiwana `expected_data[k]` równa się wynikowi ALU dla `send_data[k-1]` (sprawdzone bezpośrednio na netliście ALU: 552/553 + pierwszy wektor = stan po resecie).
- Master generuje **29 impulsów SCLK** na ramkę 28-bitową (zmierzone w symulacji).

---

# Lista napraw i ulepszeń

Priorytety: **[P0]** psuje build albo test, **[P1]** błąd projektowy lub funkcjonalny, **[P2]** jakość i utrzymanie. Punkty, które zniknęły po usunięciu jednostek 2 i 3, są oznaczone jako **nieaktualne**.

## A. Architektura / protokół PiCoRe

**A1 [P2] Brak wyboru slave'a.**
Master ma jedno `o_ss`, a parametr `SLAVES_NUMBER = 3` jest nieużywany. Przy jednym slave'ie nie ma to znaczenia, ale dołożenie kolejnych wymaga zmian.
- Naprawa: `output logic [SLAVES_NUMBER-1:0] o_ss_n`, wejście `i_slave_sel`, osobna linia CS dla każdego slave'a. Do tego czasu ustawić `SLAVES_NUMBER = 1` albo go usunąć.

**A2 [P2] MISO nie jest trójstanowe.**
`o_miso` slave'a jest sterowane zawsze, także przy nieaktywnym CS. Przy jednym slave'ie to nie przeszkadza, na wspólnej magistrali już tak.
- Naprawa: `assign o_miso = i_cs ? 1'bz : s_miso_bit;` albo osobne `o_miso_oe`.

**A3 [P1] Off-by-one w `watchdog`, który rozjeżdża format ramki.**
Licznik liczy `i_cycles…0` włącznie, więc okres wynosi `i_cycles+1`. Slave ustawia 8, dostaje okno 9 bitów i jeden bit ramki przepada. Tak powstały separatory `0` na bitach 19 i 10 oraz 6 bitów wypełnienia.
- Naprawa: ładować `i_cycles-1` albo zgłaszać `o_inter` przy `s_count == 1`. Potem przeprojektować ramkę do zwartej postaci `A[8] B[8] OP[4]` (20 bitów) i przeliczyć wektory. **Uwaga:** poprawienie tylko jednego licznika psuje protokół, patrz [DOC/dziwactwa.md §1](DOC/dziwactwa.md#1-dwa-off-by-oney-które-się-znoszą).

**A4 [P1] 29 impulsów SCLK na ramkę 28 bitów, pierwszy impuls jest stracony.**
MOSI jest ustawiane na zboczu opadającym, więc przy pierwszym narastającym zboczu na linii nie ma jeszcze bitu 27. Slave zużywa ten impuls na przejście `READY→LOAD_A`, a 29. impuls wpisuje wynik do rejestru wyjściowego slave'a.
- Naprawa (tryb 0, CPHA=0): pierwszy bit ma leżeć na MOSI już przy opadnięciu SS (preload), a transfer ma mieć dokładnie `BITS` zboczy. Slave potrzebuje wtedy własnego zegara albo innego momentu na wpis wyniku.

**A5 [P1] MISO zmienia się na tym samym zboczu, na którym master je próbkuje.**
Slave przesuwa `shift_out` na `posedge sclk`, a master próbkuje `i_miso` również na `posedge`. W symulacji zero-delay ratują to przypisania nieblokujące, w sprzęcie grozi to naruszeniem hold.
- Naprawa: slave wystawia MISO na `negedge sclk` (tryb 0), master próbkuje na `posedge` bez dodatkowego rejestru `s_bit_in`.

**A6 [P1] SCLK jest wyjściem kombinacyjnym FSM i jednocześnie zegarem wewnętrznych przerzutników.**
`o_sclk` (a także `o_ss` i `o_busy`) to dekodowanie stanu, co grozi glitchami.
- Naprawa: SCLK z przerzutnika, cała logika mastera na `i_clk` z clock-enable. Opcjonalnie parametr dzielnika SCLK.

**A7 [P1] Slave nie resynchronizuje się na CS.**
`i_cs` jest sprawdzane tylko w stanie `READY`. Przerwana ramka zostawia FSM w środku ramki aż do resetu.
- Naprawa: nieaktywny CS ma zerować FSM, licznik i shifter.

**A8 [P2] Wynik wraca z opóźnieniem jednej ramki.**
Jest to udokumentowane w `DOC/protokol_picore.md`, ale protokół tego nie sygnalizuje. Pierwsza ramka po resecie zwraca zera.
- Naprawa: bit „valid” w odpowiedzi albo ramka typu NOP/READ.

**A9 [P2] Brak parametryzacji trybu zegara (CPOL/CPHA), kolejności bitów i długości ramki.**

## B. Build / skrypty

**B1 [P0] Brakujący katalog `DOC/` wywala `make rtl`.**
`picore_slave.ys` wykonuje `write_json ../DOC/picore_slave.json`.
- Naprawa: `mkdir -p ../DOC ../RTL` w Makefile albo usunąć `write_json`.
- **Status:** obejście działa, bo katalog `DOC/` istnieje w repozytorium razem z dokumentacją.

**B2 [P0] `make sim` nie zależy od `rtl`.**
`RTL/` jest w `.gitignore`, więc na świeżym klonie `make sim` nie ma czego kompilować.
- Naprawa: `sim: rtl clear`, albo reguły plikowe.

**B3 [P2] Makefile:**
- brak `.PHONY`;
- cel nazywa się `clear` zamiast `clean` i nie usuwa `*.log`, `waves.vcd` ani `RTL/*`;
- brak celu do symulacji modeli (pre-synteza).

**B4 [P2] Skrypty `.ys`:**
- „zmiana nazwy” przez `copy`/`delete` zamienić na `rename X X_rtl`;
- `flatten` po `synth`/`abc` zamienić na `synth -flatten -top X`;
- `-top` jest podany tylko w `picore_slave.ys`.

**B5 [P2] Zduplikowane moduły pomocnicze.**
`shifter` i `watchdog` są zdefiniowane w `PICORE_MASTER/` i `PICORE_SLAVE/`, więc `iverilog MODEL/*/*.sv` zgłasza redeklarację. Kolizje nazw ALU zniknęły razem z jednostkami 2 i 3.
- Naprawa: jedna kopia w `MODEL/COMMON/`.

**B6 [P2] Brak źródeł behawioralnych ALU.**
W repo jest tylko netlista. Tabela operacji odtworzona z netlisty znajduje się w [DOC/exe_unit_alu.md](DOC/exe_unit_alu.md).
- Naprawa: dodać źródła behawioralne.

**B7** — nieaktualne (dotyczyło nazw plików trzech ALU).

## C. Testbench

**C1** — nieaktualne. Błędny wektor dotyczył jednostki 3, która została usunięta.

**C2 [P1] Wyścigi w TB.**
- `send_request` jest przypisywane blokująco w `always @(posedge clk)` i jednocześnie z bloku `initial` (w pliku `.vh`).
- Sprawdzanie na `negedge clk` zależy od kolejności tych przypisań.

Naprawa: jeden proces sterujący (task `spi_transfer(data, expected)`), przypisania nieblokujące.

**C3 [P2] Model odniesienia zamiast twardo zakodowanych wektorów.**
Wektory pochodzą z tej samej netlisty ALU, więc test sprawdza transport PiCoRe, a nie poprawność ALU (patrz [DOC/dziwactwa.md §8](DOC/dziwactwa.md#8-weryfikacja-co-naprawdę-jest-testowane)).
- Naprawa: behawioralny model ALU w TB, losowanie argumentów, `expected_data` liczone w locie z opóźnieniem jednej ramki.

**C4 [P2] Drobne rzeczy w TB:**
- `$display("%21b")` dla 28-bitowych danych: poprawić na `%b`;
- `` `timescale 1s/1ms `` z okresem zegara 20 s: poprawić na `1ns/1ps`;
- nieużywane makra `SIMTIME` i `DATASTEP`.

**C5** — nieaktualne (`testbench_do_pliku_txt.sv`, generator wektorów dla ALU jednostki 2, usunięty).

**C6 [P2] Brak weryfikacji protokołu na poziomie przebiegów.**
Brak asercji SVA oraz testów przerwanej ramki i resetu w trakcie transferu.

## D. `picore_slave.sv` (slave)

**D1 [P0/P1] `result_enable` niezadeklarowany** (`picore_slave.sv:69`).
Yosys tworzy niejawny net, a surowsze narzędzia zgłoszą błąd. Sygnał jest nieużywany.
- Naprawa: usunąć go i dodać `` `default_nettype none ``.

**D2 [P1] 5 latchy:** `s_result`, `s_flags`, `s_argA_next`, `s_argB_next`, `s_oper_next`.
Naprawa:
- usunąć `*_next` i ładować rejestry bezpośrednio z `s_data_next`;
- do `shift_out.i_data` podać wprost `{s_result_next, s_flags_next, …}`;
- `always_comb` z wartościami domyślnymi.

**D3 [P1] Niepodłączone wejścia shifterów:** `shift_in.i_data` i `shift_out.i_bit`.
- Naprawa: tie-off `1'b0`.

**D4 [P2] Twardo zakodowane szerokości:** `{16{1'b0}}`, `s_cycles = 8`, `watchdog #(.N(4))`.
- Naprawa: wyliczać z `BITS` i `M`.

**D5 [P2] Martwy kod:**
- `s_wrt_in` jest zawsze 0;
- `{s_en_out, s_en_in} = '1` jest powtarzane w stanach, choć jest wartością domyślną;
- zakomentowane `s_bit`;
- `s_oper` ma 8 bitów, choć używane są tylko `[7:4]`.

**D6** — nieaktualne (trzy prawie identyczne wrappery).

## E. `picore_master.sv`

**E1 [P1]** Zobacz A4, A5, A6.

**E2 [P2] Ostrzeżenie Yosysa `Resizing cell port … i_cycles from 32 bits to 6 bits`.**
- Naprawa: `.i_cycles(($clog2(BITS)+1)'(BITS))`.

**E3 [P2] Martwe sygnały i redundancja:**
- `s_sin_en` i `s_sin_wrt` są nieużywane;
- ustawienia w stanie `STATE_SS` nie mają skutku;
- `SLAVES_NUMBER` jest nieużywany.

**E4 [P2] `o_data` to „żywa” zawartość shiftera.**
- Naprawa: rejestr wyjściowy plus impuls `o_done`.

**E5 [P2] `i_send` jest poziomowe.**
Warto to udokumentować albo reagować na zbocze.

## F. `shifter.sv` / `watchdog.sv`

**F1 [P2]** `{s_shifter, i_bit}` to niejawne obcięcie N+1→N bitów. Zapisać jako `{s_shifter[N-2:0], i_bit}`.

**F2 [P2]** `watchdog` to przeładowywany licznik bitów (nie watchdog), więc warto zmienić nazwę. Do tego off-by-one z A3.

**F3 [P2]** Pomieszane `always_ff` i `always @(*)`. Kopia mastera ma `always_ff`, a kopia slave'a `always`.

**F4 [P2]** Niespójna konwencja resetu: `i_rst` vs `i_rst_n` (wszędzie active-low).

## G. Repozytorium / dokumentacja

- **G1 [P2]** Dodać CI (`make rtl sim`, fail przy błędnych transferach).
- **G2 [P2]** Dodać lint (Verilator `--lint-only -Wall`) i `` `default_nettype none ``.
- **G3** — zrobione ([DOC/exe_unit_alu.md](DOC/exe_unit_alu.md)).
- **G4 [P2]** Komentarze są po polsku bez znaków diakrytycznych, a identyfikatory po angielsku. Wybrać jedną konwencję.

## Proponowana kolejność prac

1. B1, B2, D1: pewny build na świeżym klonie.
2. D2, D3, B5: brak latchy i wspólna kompilacja modeli.
3. A6, A5, A4, A3: czysty timing (jak w trybie 0 SPI) i zwarta ramka, z przeliczeniem wektorów (najlepiej od razu C3).
4. A7, potem ewentualnie A1 i A2, jeśli wróci multi-slave.
5. Pozostałe P2.
