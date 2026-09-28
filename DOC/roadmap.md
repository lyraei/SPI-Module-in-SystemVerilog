# Roadmapa PiCoRe

Propozycje rozwoju, które zachowują tożsamość projektu. Każdy etap powinien dalej pasować do trzech liter nazwy:

- **Pi**pelined: odpowiedź płynie z opóźnieniem, a łącze nie czeka na wynik;
- **Co**mmand: master wysyła polecenia;
- **Re**sponse: slave odpowiada ramkami odpowiedzi.

Etapy są uporządkowane od fundamentów do zabawek. Numery punktów w nawiasach (A3, D2…) odnoszą się do [listy napraw w README](../README.md#lista-napraw-i-ulepszeń).

---

## Etap 0: porządek w nazwach

- ~~Przemianować pliki, katalogi i skrypty~~: **zrobione** (`MODEL/PICORE_MASTER/picore_master.sv`, `MODEL/PICORE_SLAVE/picore_slave.sv`, `WORK/picore_*.ys`, `RTL/picore_*_rtl.sv`).
- Przemianować to, co zostało po staremu. Poniżej pełna lista, stan po przemianowaniu plików i katalogów. Wszystkie te zmiany dotykają HDL albo zależą od zmian w HDL, więc warto je zrobić jednym commitem i od razu sprawdzić `make rtl sim`.

  **Nazwy modułów (HDL)**

  | Gdzie | Obecnie | Proponowana nazwa |
  |---|---|---|
  | `MODEL/PICORE_MASTER/picore_master.sv:1` | `module spi_master` | `picore_master` |
  | `MODEL/PICORE_SLAVE/picore_slave.sv:1` | `module spi_exe_unit_1` | `picore_slave_alu` (albo `picore_slave`) |
  | `MODEL/PICORE_SLAVE/exe_unit_1_rtl.sv` | `module exe_unit_rtl` w pliku z numerem jednostki | moduł `picore_alu`, plik `picore_alu_rtl.sv` |
  | `MODEL/PICORE_SLAVE/picore_slave.sv` | instancja ALU `exe1` | `alu` |

  **Skrypty Yosysa**: nazwy modułów są w poleceniach, a nie tylko w ścieżkach

  | Gdzie | Obecnie | Po zmianie |
  |---|---|---|
  | `WORK/picore_master.ys:12,14` | `copy spi_master spi_master_rtl`, `select -del spi_master_rtl` | `picore_master` / `picore_master_rtl` |
  | `WORK/picore_slave.ys:3` | `prep -top spi_exe_unit_1` | `prep -top picore_slave_alu` |
  | `WORK/picore_slave.ys:12,14` | `copy spi_exe_unit_1 spi_exe_unit_1_rtl`, `select -del …` | `picore_slave_alu` / `picore_slave_alu_rtl` |

  Moduły w wygenerowanych netlistach (`spi_master_rtl`, `spi_exe_unit_1_rtl`) zmienią nazwę same po zmianie tych poleceń.

  **Testbench (`TEST/testbench.sv`)**

  | Linia | Obecnie | Po zmianie |
  |---|---|---|
  | 23, 31, 47 | komentarze „interfejsu SPI”, „komunikacji SPI”, „z interfejsem SPI” | „PiCoRe” |
  | 24–25 | sygnały `spi_mosi`, `spi_miso`, `spi_sclk`, `spi_ss` | `pc_cmd`, `pc_rsp`, `pc_clk`, `pc_sel_n` (albo `picore_*`) |
  | 32–33 | `spi_master_rtl spi_master (…)` | `picore_master_rtl master (…)` |
  | 48–49 | `spi_exe_unit_1_rtl spi_exe_unit_1 (…)` | `picore_slave_alu_rtl slave (…)` |
  | 96 | komentarz „Testy ukladu spi_exe_unit_1” | nazwa nowego modułu |
  | 97 | `` `include "../TEST/test_spi_exe_unit_1.vh" `` | `` `include "../TEST/picore_vectors.vh" `` |

  **Pliki**

  | Obecnie | Po zmianie | Uwagi |
  |---|---|---|
  | `TEST/test_spi_exe_unit_1.vh` | `TEST/picore_vectors.vh` | razem z linią 97 testbencha |
  | `MODEL/PICORE_SLAVE/exe_unit_1_rtl.sv` | `MODEL/PICORE_SLAVE/picore_alu_rtl.sv` | numer jednostki to relikt po trzech ALU |

  **Porty w stylu SPI** (opcjonalnie, zależnie od decyzji o nazwach linii, patrz niżej)

  | Moduł | Obecne porty | Propozycja |
  |---|---|---|
  | master | `o_sclk`, `o_mosi`, `i_miso`, `o_ss` | `o_pclk`, `o_cmd`, `i_rsp`, `o_sel_n` |
  | slave | `i_sclk`, `i_mosi`, `o_miso`, `i_cs` | `i_pclk`, `i_cmd`, `o_rsp`, `i_sel_n` |

  **Poza kodem**

  - `.gitignore`: po przejściu na nowe nazwy usunąć linię `RTL/spi*` (zostawiona dla starych, lokalnych netlist).
  - Dokumentacja (`README.md`, `DOC/*`): wszystkie wzmianki „moduł `spi_master`”, „`spi_exe_unit_1`”, „sygnały `spi_*`”, „`test_spi_exe_unit_1.vh`” oraz notki „nazwa sprzed zmiany” w `picore_master.md` i `picore_slave.md`. Opisy historyczne w `dziwactwa.md` §5 zostają.
  - Nazwa repozytorium na GitHubie (`SPI-Module-in-SystemVerilog`) i opis repo („Master and Slaves modules connected via SPI interface”): patrz ostatni punkt tego etapu.
  - Lokalny katalog klonu: `SPI-Module-in-SystemVerilog/` można przemianować dowolnie, git tego nie śledzi.
- Nazwy linii: zostawić `SCLK/MOSI/MISO/SS` (czytelne dla każdego) albo przejść na własne, np. `PCLK`, `CMD` (master→slave), `RSP` (slave→master), `SEL_n`. Własne nazwy mówią wprost „to nie jest SPI”.
- Wspólne `shifter`/`watchdog` przenieść do `MODEL/COMMON/` (B5), a `watchdog` przemianować na `bit_counter` (F2).
- Zmienić nazwę repozytorium na GitHubie: Settings → General → Repository name, np. `PiCoRe`, oraz opis repo (About → ⚙). Stare URL-e przekierowują automatycznie, a lokalnie wystarczy `git remote set-url origin https://github.com/lyraei/PiCoRe`.

## Etap 1: solidne fundamenty (naprawy z README)

Kolejność ma znaczenie, bo dwa off-by-one'y się znoszą ([dziwactwa.md §1](dziwactwa.md#1-dwa-off-by-oney-które-się-znoszą)). Naprawiać trzeba je w pakiecie.

1. **Master w jednej domenie zegarowej (A6).** SCLK z przerzutnika, a cała logika na `i_clk` z sygnałami „strobe” zbocza. Dzielnik SCLK jako parametr.
2. **Czysty timing (A4, A5).** Pierwszy bit gotowy przy opadnięciu SEL, dokładnie N zboczy na N bitów, a odpowiedź zmieniana na zboczu przeciwnym do próbkowania.
3. **Licznik bez off-by-one (A3)** i **zwarta ramka.** Na razie `A[8] B[8] OP[4]` = 20 bitów.
4. **Slave odporny na przerwaną ramkę (A7).** Nieaktywny SEL zeruje FSM i liczniki.
5. **Bez latchy (D2)** oraz `` `default_nettype none `` (D1, G2).
6. **Źródło behawioralne ALU.** Przepisać na RTL według tabeli z [exe_unit_alu.md](exe_unit_alu.md) i zweryfikować przeciwko starej netliście (1 048 576 kombinacji, jak przy odtwarzaniu tabeli).
7. **Testbench z modelem referencyjnym (C3).** Losowe polecenia, a oczekiwana odpowiedź liczona z modelu z uwzględnieniem potoku.
8. **CI (G1).** GitHub Actions z `yosys` + `iverilog` i fail przy jakimkolwiek błędnym transferze.

## Etap 2: PiCoRe v1, czyli prawdziwy protokół

Obecny „protokół” to ALU przyklejone do rejestru przesuwnego. Wersja 1 powinna mieć specyfikację, która przeżyje zmianę slave'a.

### Ramka polecenia (master → slave)

```
| CMD[7:0] | TAG[3:0] | LEN[3:0] | PAYLOAD[LEN bajtów] | CRC8 |
```

### Ramka odpowiedzi (slave → master, w następnej ramce)

```
| STATUS[7:0] | TAG[3:0] | LEN[3:0] | PAYLOAD | CRC8 |
```

- **TAG** czyni potok jawnym, bo odpowiedź mówi, na które polecenie odpowiada. Znika problem „czyj to wynik?”, który kiedyś zepsuł test jednostki 3.
- **STATUS** zawiera co najmniej: `VALID` (odpowiedź niesie dane), `ERR_CMD` (nieznane polecenie), `ERR_CRC` (polecenie przyszło uszkodzone) i `BUSY` (wynik jeszcze się liczy).
- **Polecenie `NOP`** wypycha ostatnią odpowiedź z potoku bez zlecania nowej pracy.
- **Prawdziwe CRC-8** (np. wielomian 0x07) zamiast obecnego „CRC”, które jest tylko obciętym iloczynem wielomianów. Ironia do naprawienia.
- Protokół warto spisać jako osobny `DOC/spec_v1.md`, z przebiegami w [WaveDrom](https://wavedrom.com/).

## Etap 3: slave jako urządzenie z rejestrami

- **Zestaw poleceń:**

  | Polecenie | Działanie |
  |---|---|
  | `READ_REG` | odczyt rejestru |
  | `WRITE_REG` | zapis rejestru |
  | `EXEC` | uruchomienie operacji ALU |
  | `NOP` | wypchnięcie odpowiedzi z potoku |
  | `RESET` | reset slave'a |

- **Mapa rejestrów:**

  | Rejestr | Rola |
  |---|---|
  | `ID` / `VERSION` | stałe, np. `0x9C`: szybki test łącza |
  | `STATUS` | stan slave'a |
  | `CONFIG` | konfiguracja |
  | `ACC` | akumulator |

- **Akumulator:** `EXEC` z trybem „A = ACC” pozwala łańcuchować obliczenia bez przesyłania wyniku tam i z powrotem.
- **Wiele slave'ów różnego typu za tym samym protokołem:** ALU, rejestr GPIO, generator liczb losowych (xorshift), timer. Master nie musi wiedzieć, co jest po drugiej stronie, bo pyta o `ID`.

## Etap 4: głębszy potok i dłuższe operacje

- **Potok o głębokości N z kolejką FIFO poleceń w slave'ie.** Master może wysłać kilka poleceń naraz, a odpowiedzi wracają z tagami.
- **Operacje wielotaktowe:** mnożenie, dzielenie, CORDIC (sin/cos), pierwiastek. Slave odpowiada `BUSY`, a wynik przychodzi w którejś z kolejnych ramek z właściwym tagiem. To esencja „pipelined command/response”.
- Opcjonalnie **odpowiedzi poza kolejnością**: tagi to umożliwiają, a szybkie polecenia nie czekają na wolne.
- **Kredyty:** slave mówi w `STATUS`, ile ma wolnych miejsc w kolejce, więc master nie przepełni FIFO.

## Etap 5: topologie

- **Osobne linie SEL** dla każdego slave'a i trójstanowe RSP (A1, A2): klasyczna gwiazda.
- **Daisy-chain.** Wyjście RSP jednego slave'a to wejście CMD kolejnego. Każdy slave dokłada jedną ramkę opóźnienia, więc łańcuch sam w sobie jest potokiem, co bardzo pasuje do nazwy. Polecenie niesie adres albo licznik przeskoków.
- **Adresowanie w nagłówku** na wspólnej magistrali: pole `ADDR` w `CMD`, a odpowiada tylko zaadresowany slave.

## Etap 6: szybkość i fizyka

- **Slave z własnym zegarem** i synchronizatorami (CDC). Uniezależnia to obliczenia od SCLK (dziś slave „żyje” tylko, gdy master kręci korbą).
- **DDR:** dane na obu zboczach PCLK.
- **Wiele linii danych** (x2, x4) na wzór QSPI, jako opcja negocjowana przez `CONFIG`.
- **Auto-kalibracja opóźnienia próbkowania** po stronie mastera przy wyższych częstotliwościach.

## Etap 7: sprzęt i narzędzia

- **FPGA:** np. iCE40 lub ECP5 z otwartym toolchainem (Yosys + nextpnr), co pasuje do obecnego flow. Mastera i slave'a można mieć na jednej płytce albo na dwóch połączonych kabelkiem.
- **Most do PC:** UART lub USB ↔ master PiCoRe plus prosty CLI w Pythonie (`picore exec add 5 3`).
- **Sterownik na mikrokontroler:** implementacja mastera bit-bang w C (RP2040, STM32, AVR) i biblioteka `libpicore`.
- **Weryfikacja formalna** w SymbiYosys: asercje „dokładnie N zboczy na ramkę”, „odpowiedź z tagiem k przychodzi po poleceniu k”, „brak utraty poleceń przy pełnym FIFO”.
- **cocotb:** testbench w Pythonie z modelem referencyjnym, wygodniejszy niż wektory w plikach `.vh`.

## Etap 8: zabawki

- **Koprocesor dla soft-CPU.** Np. PicoRV32 (uwaga na zbieżność nazw PicoRV / PiCoRe, co może być zabawne albo mylące) z mostem z instrukcji custom do poleceń PiCoRe.
- **Demo na żywo:** slave-kalkulator z wyświetlaczem 7-segmentowym, a master sterowany z klawiatury.
- **„Benchmark potoku”:** ile poleceń na sekundę przy głębokości potoku 1, 2, 4 i 8. Ładny wykres do README.

---

## Proponowana kolejność

1. Etap 0 i 1: czysta baza, CI, model referencyjny.
2. Etap 2: spec v1 z tagiem, statusem i CRC. To moment, w którym PiCoRe staje się protokołem, a nie tylko układem.
3. Etap 3: rejestry i `ID`.
4. Etapy 4 i 5, zależnie od tego, co bardziej kręci: głębszy potok czy wiele slave'ów.
5. Etapy 6–8 hobbystycznie, w dowolnej kolejności.
