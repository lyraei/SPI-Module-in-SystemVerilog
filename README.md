# SPI Module in SystemVerilog

Master SPI komunikujący się z trzema slave'ami. Każdy slave to jednostka wykonawcza (ALU, `exe_unit`), która przyjmuje w ramce dwa argumenty i kod operacji, a wynik z flagami odsyła w **następnej** ramce. Moduły opisane są w SystemVerilogu, syntezowane Yosysem do netlisty bramek AND/OR/XOR, a netlisty symulowane są w Icarus Verilog.

**Pełna dokumentacja: [`DOC/`](DOC/README.md)**. Zawiera opis każdego pliku, działanie interfejsu SPI zbocze po zboczu i kompletne tabele operacji oraz flag wszystkich trzech ALU.

## Struktura

| Ścieżka | Zawartość |
|---|---|
| `MODEL/SPI_MASTER/spi_master.sv` | Master SPI: FSM `READY→SS→LOAD→LOW⇄HIGH→END`, SCLK = `i_clk`/2, ramka 28 bitów, MSB first |
| `MODEL/SPI_EXE_UNIT_{1,2,3}/spi_exe_unit_N.sv` | Slave: FSM `READY→LOAD_A→LOAD_B→LOAD_OPER→STORE_RESULT` + ALU |
| `MODEL/SPI_EXE_UNIT_N/exe_unit*_rtl.sv` | Gotowe netlisty ALU wygenerowane przez Yosysa (bez źródeł behawioralnych) |
| `MODEL/*/shifter.sv` | Rejestr przesuwny z wpisem równoległym (4 identyczne kopie) |
| `MODEL/*/watchdog.sv` | Przeładowywany licznik w dół z wyjściem `o_inter` (4 identyczne kopie) |
| `WORK/*.ys`, `WORK/makefile` | Skrypty syntezy Yosysa i Makefile (`rtl`, `sim`, `wave`) |
| `TEST/testbench.sv` | Testbench netlist: master + 3 slave'y, MISO wybierany multiplekserem w TB |
| `TEST/test_spi_exe_unit_N.vh` | Wektory testowe (553 / 2000 / 58 transferów) |
| `TEST/testbench_do_pliku_txt.sv` | Stary generator wektorów, dziś niekompilowalny (patrz niżej) |

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

Kolejność flag jest inna w każdej jednostce:

| Jednostka | Flagi `[0]`, `[1]`, `[2]`, `[3]` |
|---|---|
| 1 | SF, OF, NF, BF |
| 2 | VF, BF, SF, OF |
| 3 | OF, SF, ZF, PF |

## Uruchomienie

```bash
mkdir -p RTL            # na wypadek, gdyby checkout pominął pusty katalog
cd WORK
make rtl                # synteza Yosysem -> ../RTL/*_rtl.sv
make sim                # iverilog + uruchomienie
make wave               # gtkwave waves.vcd
```

Wymagane narzędzia: `yosys`, `iverilog` (sprawdzone na wersji 12), opcjonalnie `gtkwave`.

## Stan weryfikacji (sprawdzone)

- Synteza wszystkich 4 skryptów przechodzi, **pod warunkiem że istnieje `DOC/`**.
- Yosys zgłasza **15 latchy** (po 5 na slave'a) i niejawną deklarację `result_enable` w jednostce 1.
- Symulacja kończy się wynikiem **2610 poprawnych i 1 błędny transfer**. Błędny jest pierwszy wektor `test_spi_exe_unit_3.vh`, a przyczyną jest zła wartość oczekiwana w wektorze, bo RTL działa poprawnie (patrz C1).
- Każda wartość oczekiwana `expected_data[k]` równa się wynikowi ALU dla `send_data[k-1]` (sprawdzone bezpośrednio na netlistach ALU: 552/553, 1999/2000, 57/58).
- Master generuje **29 impulsów SCLK** na ramkę 28-bitową (zmierzone w symulacji).

---

# Lista napraw i ulepszeń

Priorytety: **[P0]** psuje build albo test, **[P1]** błąd projektowy lub funkcjonalny, **[P2]** jakość i utrzymanie.

## A. Architektura / protokół SPI

**A1 [P1] Brak prawdziwego wyboru slave'a.**
Master ma jedno `o_ss`, a parametr `SLAVES_NUMBER` jest nieużywany. Testbench podpina to samo `spi_ss` do wszystkich trzech `i_cs`, więc **każdy slave odbiera i przetwarza każdą ramkę**. Wybór odbywa się wyłącznie w TB, przez multiplekser MISO.
- Naprawa: `output logic [SLAVES_NUMBER-1:0] o_ss_n`, wejście `i_slave_sel`, osobna linia CS dla każdego slave'a.

**A2 [P1] MISO nie jest trójstanowe.**
`o_miso` slave'a jest sterowane zawsze, także przy nieaktywnym CS, więc slave'ów nie da się podłączyć do wspólnej linii MISO.
- Naprawa: `assign o_miso = i_cs ? 1'bz : s_miso_bit;` albo osobne `o_miso_oe` na potrzeby syntezy (w FPGA bufor trójstanowy dopiero na pinie).

**A3 [P1] Off-by-one w `watchdog`, który rozjeżdża format ramki.**
Licznik liczy `i_cycles…0` włącznie, więc okres wynosi `i_cycles+1`. Slave ustawia 8, dostaje okno 9 bitów i jeden bit ramki przepada. Tak powstały separatory `0` na bitach 19 i 10 oraz 6 bitów wypełnienia.
- Naprawa: ładować `i_cycles-1` albo zgłaszać `o_inter` przy `s_count == 1`. Potem przeprojektować ramkę do zwartej postaci `A[8] B[8] OP[4]` (20 bitów) i przeliczyć wektory.

**A4 [P1] 29 impulsów SCLK na ramkę 28 bitów, pierwszy impuls jest stracony.**
MOSI jest ustawiane na zboczu opadającym, więc przy pierwszym narastającym zboczu na linii nie ma jeszcze bitu 27. Slave zużywa ten impuls na przejście `READY→LOAD_A`, a 29. impuls wpisuje wynik do rejestru wyjściowego slave'a. Protokół działa tylko dzięki tej przypadkowej zgodności.
- Naprawa (tryb 0, CPHA=0): pierwszy bit ma leżeć na MOSI już przy opadnięciu SS (preload), a transfer ma mieć dokładnie `BITS` zboczy. Slave powinien zaczynać odbiór od pierwszego zbocza po aktywacji CS.

**A5 [P1] MISO zmienia się na tym samym zboczu, na którym master je próbkuje.**
Slave przesuwa `shift_out` na `posedge sclk`, a master próbkuje `i_miso` również na `posedge`. W symulacji zero-delay ratują to przypisania nieblokujące, w sprzęcie grozi to naruszeniem hold. Dodatkowy rejestr `s_bit_in` w masterze to obejście, które dokłada bit opóźnienia.
- Naprawa: slave wystawia MISO na `negedge sclk` (tryb 0), master próbkuje na `posedge` bez dodatkowego rejestru.

**A6 [P1] SCLK jest wyjściem kombinacyjnym FSM i jednocześnie zegarem wewnętrznych przerzutników.**
`o_sclk` (a także `o_ss` i `o_busy`) to dekodowanie stanu, co grozi glitchami. Shifter, watchdog i rejestry MOSI/MISO mastera są taktowane tym sygnałem, czyli zegarem generowanym z logiki.
- Naprawa: SCLK z przerzutnika (`always_ff @(posedge i_clk) sclk <= …`). Cała logika mastera na `i_clk` z clock-enable, generowanym jako strobe zbocza narastającego/opadającego SCLK. Opcjonalnie parametr dzielnika SCLK.

**A7 [P1] Slave nie resynchronizuje się na CS.**
`i_cs` jest sprawdzane tylko w stanie `READY`, synchronicznie do SCLK. Przerwana ramka (CS wraca do `1` w trakcie transferu) zostawia FSM w środku ramki aż do resetu, a następna ramka zostanie źle zdekodowana.
- Naprawa: CS nieaktywny ma zerować FSM, licznik i shifter (asynchronicznie `negedge i_rst or posedge i_cs` albo sprawdzanie CS w każdym stanie). Idealnie synchronizacja SCLK/CS/MOSI do zegara systemowego slave'a.

**A8 [P2] Wynik wraca z opóźnieniem jednej ramki. To poprawne, ale nieudokumentowane i nieobsłużone.**
Pierwsza ramka po resecie oraz pierwsza ramka po zmianie slave'a zwracają wynik poprzedniej operacji, obliczony z ramki skierowanej do innego slave'a (skutek A1).
- Naprawa: udokumentować, dodać bit „valid” w odpowiedzi albo ramkę typu NOP/READ.

**A9 [P2] Brak parametryzacji trybu SPI (CPOL/CPHA), kolejności bitów i długości ramki.**

## B. Build / skrypty

**B1 [P0] Brakujący katalog `DOC/` wywala `make rtl`.**
`spi_slave_1.ys` wykonuje `write_json ../DOC/spi_exe_unit_1.json` i kończy się błędem `Can't open output file`. Pozostałe slave'y nie mają tego kroku, co jest niespójne.
- Naprawa: dodać `DOC/.gitkeep` albo `mkdir -p ../DOC ../RTL` w Makefile, ewentualnie usunąć `write_json`.
- **Status:** obejście działa, bo katalog `DOC/` istnieje teraz w repozytorium razem z dokumentacją. Właściwa poprawka (`mkdir` w Makefile) nadal jest do zrobienia.

**B2 [P0] `make sim` nie zależy od `rtl`.**
`RTL/` jest w `.gitignore`, więc na świeżym klonie `make sim` nie ma czego kompilować.
- Naprawa: `sim: rtl clear`, albo reguły plikowe `../RTL/%_rtl.sv: %.ys ...`.

**B3 [P2] Makefile:**
- brak `.PHONY`;
- cel nazywa się `clear` zamiast `clean` i nie usuwa `*.log`, `waves.vcd` ani `RTL/*`;
- brak celu do symulacji modeli (pre-synteza), co utrudnia debug.

**B4 [P2] Skrypty `.ys`:**
- „zmiana nazwy” przez `copy X X_rtl; select -del X_rtl; delete` zamienić na `rename X X_rtl`;
- `flatten` jest wykonywany po `synth`/`abc`, a lepiej `synth -flatten -top X`;
- `-top` jest podany tylko w `spi_slave_1.ys`;
- 4 prawie identyczne skrypty zastąpić jednym szablonem sterowanym zmiennymi Makefile.

**B5 [P1] Kolizje nazw modułów uniemożliwiają wspólną kompilację modeli.**
`iverilog MODEL/*/*.sv` zgłasza błędy z trzech powodów:
- `shifter` i `watchdog` są zdefiniowane 4 razy;
- `exe_unit_rtl` występuje w jednostce 1 i 3;
- `$paramod…\crc_eval` występuje w jednostce 1 i 2.

Naprawa:
- jedna kopia `shifter.sv` i `watchdog.sv` w `MODEL/COMMON/`;
- unikalne nazwy ALU: `exe_unit_1_rtl`, `exe_unit_2_rtl`, `exe_unit_3_rtl`;
- ponowna synteza netlist ALU z unikalnymi nazwami podmodułów, albo po prostu z `flatten`.

**B6 [P2] Brak źródeł behawioralnych ALU.**
W repo są tylko netlisty. Nie wiadomo, jakie operacje oznaczają kody `PPPP` ani jak liczone są flagi. Nazwy podmodułów (`crc_eval`, `u2togray`, `zero_counter`, `thermometer_encoder`, …) sugerują, że pochodzą z wcześniejszych ćwiczeń.
- Naprawa: dodać źródła albo przynajmniej tabelę operacji i flag.

**B7 [P2] Niespójne nazwy plików ALU:** `exe_unit_1_rtl.sv`, `exe_unit_rtl_2.sv`, `exe_unit_rtl.sv`.

## C. Testbench

**C1 [P0] Błędny pierwszy wektor w `test_spi_exe_unit_3.vh`.**
Wektor oczekuje `0000000001000…`. Slave 3 poprawnie zwraca `0010111110000…`, czyli ALU3 z ostatniej ramki pliku unit 2 (skutek A1 i A8). To jedyny błąd w symulacji.
- Naprawa: poprawić wartość oczekiwaną albo, lepiej, na początku każdej sekcji wysłać ramkę „rozbiegową” bez sprawdzania.

**C2 [P1] Wyścigi w TB.**
- `send_request` jest przypisywane blokująco w `always @(posedge clk)` i jednocześnie z bloku `initial` (w plikach `.vh`).
- Sprawdzanie na `negedge clk` zależy od kolejności tych przypisań.

Naprawa: jeden proces sterujący (task `spi_transfer(data, expected)`), przypisania nieblokujące, synchronizacja po `master_busy`.

**C3 [P2] Model odniesienia zamiast twardo zakodowanych wektorów.**
10k linii wektorów zastąpić behawioralnym modelem ALU w TB i losowaniem argumentów. `expected_data` liczone w locie z uwzględnieniem opóźnienia jednej ramki.

**C4 [P2] Drobne rzeczy w TB:**
- `$display("%21b")` dla 28-bitowych danych: poprawić na `%28b` albo `%b`;
- `case(select_slave)` bez `default` (latch w TB);
- `select_slave` jako `integer`;
- `` `timescale 1s/1ms `` z okresem zegara 20 s jest absurdalne: poprawić na `1ns/1ps`.

**C5 [P1] `testbench_do_pliku_txt.sv` jest martwy i błędny:**
- instancjonuje nieistniejący moduł `exe_unit` (model);
- warunek jest odwrócony: wypisuje wektor, gdy wyniki są **zgodne**, i liczy to jako „błąd”;
- liczniki flag nigdy nie są aktualizowane;
- `s_flags_*` ma szerokość `[M-1:0]` zamiast 4 bitów;
- mapowanie flag (OF, SF, BF, VF) jest odwrotne niż w `spi_exe_unit_2`;
- `expected_data` jest drukowane jako 12-bitowy literał bez opóźnienia jednej ramki (to nie tą wersją wygenerowano obecne wektory);
- komentarz mówi `< 10`, a kod ma `< 11`;
- w `%c[1:32m` jest dwukropek zamiast średnika.

Naprawa: usunąć albo przepisać na generator zgodny z formatem z A3/A8.

**C6 [P2] Brak weryfikacji protokołu na poziomie przebiegów.**
Nie ma asercji SVA (liczba zboczy SCLK na ramkę, stabilność MOSI przy zboczu próbkującym, brak zmian CS w trakcie ramki). Nie ma też testu przerwanej ramki ani resetu w trakcie transferu.

## D. `spi_exe_unit_N.sv` (slave)

**D1 [P0/P1] `result_enable` niezadeklarowany w jednostce 1** (`spi_exe_unit_1.sv:69`).
Yosys tworzy niejawny net, a surowsze narzędzia (Verilator, Vivado z `default_nettype none`) zgłoszą błąd. We wszystkich jednostkach sygnał jest nieużywany.
- Naprawa: usunąć go i dodać `` `default_nettype none `` na początku plików.

**D2 [P1] 15 latchy (po 5 na slave'a):** `s_result`, `s_flags`, `s_argA_next`, `s_argB_next`, `s_oper_next`.
Przypisywane tylko w niektórych gałęziach `always @(*)`. Latch `s_result`/`s_flags` jest przezroczysty tylko w stanie `STORE_RESULT`, a jego enable to dekodowanie stanu, więc możliwe są glitche.

Naprawa:
- usunąć `*_next`;
- rejestry A, B i OP ładować bezpośrednio `s_data_next` przy `*_enable`;
- do `shift_out.i_data` podać wprost `{s_result_next, s_flags_next, …}` (wpis i tak następuje tylko przy `s_wrt_out`);
- blok kombinacyjny jako `always_comb`, z wartościami domyślnymi dla wszystkiego.

**D3 [P1] Niepodłączone wejścia shifterów:**
- `shift_in.i_data` jest bez połączenia; nieużywane, bo `i_wrt=0`, ale wisi w powietrzu;
- `shift_out.i_bit` jest bez połączenia, więc do MISO wsuwa się `z`/`x` po wysunięciu 28 bitów (dziś maskuje to 29. zbocze i reset między ramkami).

Naprawa: tie-off `1'b0`.

**D4 [P2] Twardo zakodowane szerokości.**
`{16{1'b0}}` zakłada `BITS=28` (zmiana `BITS` psuje moduł), a `s_cycles = 8` i `watchdog #(.N(4))` nie wynikają z `M`.
- Naprawa: `{(BITS-M-4){1'b0}}`, `s_cycles = M` (po A3), `N($clog2(M+1))`.

**D5 [P2] Martwy kod:**
- `s_wrt_in` jest zawsze 0;
- `{s_en_out, s_en_in} = '1` jest powtarzane w stanach, choć jest wartością domyślną;
- zakomentowane `s_bit`;
- `s_oper` ma 8 bitów, choć używane są tylko `[7:4]`;
- tylko jednostka 2 zeruje `s_oper_next[3:0]`, co jest niespójne.

**D6 [P2] Trzy prawie identyczne wrappery.**
Różnią się tylko instancją ALU i mapowaniem flag. Wystarczy jeden `spi_exe_unit` sparametryzowany (np. `generate` po `UNIT_ID`) albo wrapper przyjmujący ALU przez interfejs.

## E. `spi_master.sv`

**E1 [P1]** Zobacz A1, A4, A5, A6.

**E2 [P2] Ostrzeżenie Yosysa `Resizing cell port … i_cycles from 32 bits to 6 bits`.**
- Naprawa: `.i_cycles(($clog2(BITS)+1)'(BITS))` albo localparam o właściwej szerokości.

**E3 [P2] Martwe sygnały i redundancja:**
- `s_sin_en` i `s_sin_wrt` są nieużywane;
- w stanie `STATE_SS` ustawiane są `s_sout_en`, `s_sout_wrt` i `s_watchdog_we`, które nie mają skutku (w SS nie ma zbocza SCLK).

**E4 [P2] `o_data` to „żywa” zawartość shiftera.**
Zmienia się w trakcie transferu i nie ma strobu „dane gotowe”.
- Naprawa: rejestr wyjściowy plus impuls `o_done`/`o_valid`.

**E5 [P2] `i_send` jest poziomowe.**
Trzymane w `1` powoduje ciągłe transfery. Warto to udokumentować albo reagować na zbocze.

## F. `shifter.sv` / `watchdog.sv`

**F1 [P2]** `s_shifter_next = {s_shifter, i_bit}` to niejawne obcięcie N+1→N bitów, na które linter zgłasza ostrzeżenie. Zapisać jako `{s_shifter[N-2:0], i_bit}`.

**F2 [P2]** `watchdog` to w rzeczywistości przeładowywany timer lub licznik bitów (nie watchdog), więc warto zmienić nazwę. Do tego off-by-one z A3. `o_inter` jest kombinacyjne, co jest OK, ale trzeba to udokumentować.

**F3 [P2]** Pomieszane `always_ff` i `always @(*)`. Ujednolicić na `always_ff`/`always_comb`.

**F4 [P2]** Niespójna konwencja resetu: `i_rst` w masterze i slave'ach vs `i_rst_n` w shifterze i watchdogu. Wszędzie jest active-low, więc nazwać wszędzie `i_rst_n`.

## G. Repozytorium / dokumentacja

- **G1 [P2]** Dodać CI (GitHub Actions: `apt install yosys iverilog` → `make rtl sim`, fail przy `Liczba blednych transferow > 0`).
- **G2 [P2]** Dodać lint (Verilator `--lint-only -Wall`) i `` `default_nettype none ``.
- **G3 [P2]** Opisać tabelę operacji ALU i znaczenie flag dla każdej jednostki.
- **G4 [P2]** Komentarze są po polsku bez znaków diakrytycznych, a identyfikatory po angielsku. Wybrać jedną konwencję.

## Proponowana kolejność prac

1. B1, B2, D1, C1: zielony build i zero błędów w obecnej symulacji.
2. D2, D3, B5: brak latchy i wspólna kompilacja modeli.
3. A6, A5, A4, A3: poprawny tryb SPI 0 i zwarta ramka, z przeliczeniem wektorów (najlepiej od razu C3).
4. A1, A2, A7: prawdziwa magistrala multi-slave.
5. Pozostałe P2.
