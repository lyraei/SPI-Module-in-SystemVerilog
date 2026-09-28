# Dziwactwa i nietypowe rozwiązania

Ten dokument opisuje rozwiązania, które wyglądają na błędy albo przypadki, a w rzeczywistości trzymają układ przy życiu. Opisuje też skutki uboczne architektury. Zwykłe usterki do poprawienia (latche, niezadeklarowany `result_enable`, brak zależności w Makefile itd.) są w [liście napraw w README](../README.md#lista-napraw-i-ulepszeń).

**Najważniejsza lekcja:** protokołu nie zaprojektowano z góry. Wyłonił się z dopasowywania formatu ramki do zachowania liczników. Kilka lokalnych błędów składa się w globalną poprawność, więc każdą poprawkę protokołu trzeba robić w pakiecie. Naprawienie jednego licznika albo jednego zbocza rozsypie ramkę.

---

## 1. Dwa off-by-one'y, które się znoszą

### 1.1 Dane taktowane przez SCLK, więc pierwsze zbocze jest „fantomowe”

Rejestr przesuwny mastera jest taktowany przez `o_sclk`, a nie przez `i_clk`. Żeby wpisać `i_data` równolegle, potrzebne jest zbocze SCLK. Stan `LOAD` wystawia więc SCLK=1 wyłącznie po to, żeby załadować rejestr.

MOSI zmienia się na zboczu opadającym, więc przy tym pierwszym narastającym zboczu na linii nie ma jeszcze żadnego bitu. Slave wykorzystuje to puste zbocze do wyjścia ze stanu `READY`.

### 1.2 Licznik slave'a ma okres 9, a format ramki dopasowano do niego

`watchdog` ładowany wartością 8 liczy 8→0 i przeładowuje się dopiero na kolejnym zboczu, więc na każde pole przypada 9 zboczy. Licznika nie poprawiono. Zamiast tego w ramkę wstawiono martwe bity:

```
AAAAAAAA 0 BBBBBBBB 0 PPPP 000000
         ↑          ↑
   cykle przeładowania licznika
```

### 1.3 Arytmetyka ramki zamyka się co do zbocza

| Potrzeba slave'a | Zbocza |
|---|---|
| wyjście z `READY` | 1 |
| 3 pola × (8 bitów + 1 przeładowanie) | 27 |
| wpis wyniku do `shift_out` (`STORE_RESULT`) | 1 |
| **razem** | **29** |

Master ładuje swój licznik wartością 28 i przez ten sam off-by-one generuje **dokładnie 29** zboczy. Długość 28 bitów nie jest więc przypadkowa: 28 = 1 + 3·9, a brakujące 29. zbocze dostarcza błąd licznika mastera.

Gdyby ktoś naprawił tylko licznik mastera, slave nigdy nie wpisałby wyniku. Gdyby naprawił tylko licznik slave'a, pola rozjechałyby się względem ramki.

---

## 2. Odbiór MISO: dwa przesunięcia, które się kompensują

- **Slave przesuwa `shift_out` już na zboczu ↑#1.** W `READY` przy `cs=0` włącza `en`, więc najstarszy bit wyniku leży na MISO jeszcze przed pierwszym zboczem.
- **Master ma dodatkowy rejestr `s_bit_in`** (komentarz w kodzie: „w celu opóźnienia wejścia o jeden takt”). Próbkuje on MISO na tym samym zboczu, na którym slave je zmienia. Dzięki semantyce przypisań nieblokujących widzi wartość sprzed zbocza, czyli właściwy bit.
- **Efekt:** rejestr mastera przesuwa się 28 razy (↑#2…↑#29) i wsuwa wartości MISO widziane na ↑#1…↑#28. `o_data` kończy się więc idealnie wyrównanym słowem `{wynik, flagi, 16'b0}`.

Wygląda to na łatanie „aż zadziała”, ale bilans jest dokładny. W sprzęcie zmiana i próbkowanie na tym samym zboczu to ryzyko naruszenia hold (README A5).

---

## 3. Jeden rejestr na nadawanie i odbiór

Master nie ma osobnego bufora odbiorczego:

- bity wychodzą z MSB rejestru przesuwnego (na MOSI);
- bity wchodzą na LSB (z MISO);
- po ramce wysłane słowo jest całkowicie wypchnięte, a odebrane leży na jego miejscu.

Dlatego `o_data` to po prostu `s_shifter`, a w trakcie transmisji jest mieszanką obu słów. To klasyczny trik full-duplex, znany z SPI. Sygnały `s_sin_en`/`s_sin_wrt` to pozostałość po wersji z osobnym rejestrem wejściowym, z której zrezygnowano.

---

## 4. Potok z opóźnieniem jednej ramki

```
ramka k   : MOSI = polecenie k      MISO = wynik polecenia k−1
ramka k+1 : MOSI = polecenie k+1    MISO = wynik polecenia k
```

- **Slave nie ma własnego zegara.** Wszystko dzieje się na zboczach SCLK, więc slave pracuje tylko wtedy, gdy master „kręci korbą”. Wynik liczy się kombinacyjnie między ↑#28 a ↑#29 i na ↑#29 trafia do `shift_out`. Potem SCLK staje, więc wynik może wyjść dopiero w następnej ramce.
- **Wektory testowe to uwzględniają:** `expected_data[k]` = ALU(`send_data[k−1]`), a pierwszy wektor oczekuje zer po resecie.
- **Latch działa jak przewód.** `s_result`/`s_flags` to latch przezroczysty tylko w `STORE_RESULT`, czyli dokładnie wtedy, gdy `shift_out` robi wpis równoległy. Funkcjonalnie wyszedł z tego „rejestr ładowany jedną ścieżką”.
- **Odczyt ostatniego wyniku wymaga dodatkowej ramki**, np. samych zer.

---

## 5. Ślady architektury z trzema slave'ami i nazwy „SPI”

Projekt powstał jako magistrala z trzema slave'ami i trzema różnymi ALU, pisanymi przez trzech autorów. Zostawiono tylko jednostkę 1, ale ślady zostały:

- **Master ma parametr `SLAVES_NUMBER = 3`, nieużywany.** Wyjście SS zawsze było tylko jedno.
- **„Multi-slave” był broadcastem.** Wszystkie trzy slave'y dzieliły jedno SS, słyszały każdą ramkę i każdy liczył każde polecenie swoim ALU. Wybór odbywał się multiplekserem MISO w testbenchu, więc multi-slave było tu tylko z nazwy.
- **Skutek broadcastu:** pierwsza odpowiedź po przełączeniu slave'a była jego wynikiem dla ostatniego polecenia wysłanego do poprzedniego slave'a. Wektory jednostki 2 to przewidywały, a wektory jednostki 3 nie. Stąd jedyny błędny transfer w starej symulacji (2610/2611).
- **Nazwy zostały po trzech jednostkach:** `SPI_EXE_UNIT_1`, `spi_exe_unit_1`, `spi_slave_1.ys`, `test_spi_exe_unit_1.vh`, instancja `exe1`.
- **Plik ALU nazywa się inaczej niż moduł:** `exe_unit_1_rtl.sv` zawiera moduł `exe_unit_rtl`. Ta sama nazwa modułu była też w jednostce 3, więc nie dało się ich skompilować razem.
- **Każda netlista ALU pochodziła z innej wersji Yosysa** (0.10, 0.12, 0.13) i miała inne nazewnictwo, raz polskie (`zliczanie0`, `U1naU2`), raz angielskie (`zero_counter`, `sign_to_u2`). Projekt był więc ćwiczeniem z integracji cudzych bloków, a interfejs szeregowy był spoiwem.
- **Interfejs nazywał się „SPI”, choć nim nie jest.** Pożyczył tylko nazwy linii i ogólny kształt: CPOL=0, MSB first, rejestry przesuwne. Przy 29 zboczach na 28 bitów, pustym pierwszym zboczu i MISO zmienianym na zboczu próbkowania żadne prawdziwe urządzenie SPI by się z nim nie dogadało. Stąd zmiana nazwy na **PiCoRe**. Identyfikatory w kodzie (`spi_master`, `SPI_MASTER/`, `spi_exe_unit_1`, `spi_slave_1.ys`, sygnały `spi_*` w testbenchu) i nazwa repozytorium to relikty sprzed tej zmiany.

---

## 6. Pole opcode'u

Slave wczytuje do `s_oper` pełny bajt (bity ramki d9..d2), ale ALU dostaje tylko `s_oper[7:4]` = d9..d6. Stąd sufiks `000000` w ramce:

| Bity | Los |
|---|---|
| d9..d6 | opcode (4 bity) |
| d5..d2 | wczytane do `s_oper[3:0]` i ignorowane |
| d1, d0 | zgubione na zboczach wpisu i `STORE_RESULT` |

Pole operacji ma ten sam kształt co pola A i B, choć potrzebuje połowy miejsca. Kod slave'a jest dzięki temu symetryczny (trzy identyczne stany `LOAD_*`), a ramka MOSI marnuje 8 z 28 bitów: 2 separatory i 6 bitów sufiksu.

---

## 7. ALU: importowana netlista z niespodziankami

- **Netlista zamiast źródła.** ALU to gotowa netlista Yosysa z poprzedniego ćwiczenia, a źródeł behawioralnych brak. Tabelę operacji trzeba było odtworzyć symulacją wszystkich kombinacji wejść ([exe_unit_alu.md](exe_unit_alu.md)).
- **Flagi zależą wyłącznie od wyniku, niezależnie od opcode'u.** Nazwy są umowne:
  - `OF` oznacza „wynik = 0xFF”, a nie przepełnienie;
  - `NF` to parzystość;
  - `BF` to „wynik ma dokładnie jedną jedynkę”.
- **Nieużywane opcode'y (12–15) dają wynik 0, ale flagi dalej się liczą.** Zero ma parzystą liczbę jedynek, więc `NF=1`. Stąd wszechobecne `0000000001000…` w wektorach.
- **„CRC” to obcięte mnożenie wielomianów** na 3 najmłodszych bitach, bez dzielenia. Op 5 „liczy”, op 6 „sprawdza” (XOR z `B[6:4]`, wynik 0 oznacza „zgodne”). Para jest wewnętrznie spójna, ale z CRC ma wspólną tylko nazwę.
- **Przypadki brzegowe:**
  - liczba zer w `{A, B}` jest liczona modulo 16 (dla `A=B=0` wychodzi 0);
  - indeks najstarszej jedynki dla `A=0` wynosi 7;
  - konwersje U2↔ZM mapują „−0” (`128`) różnie w obie strony.

---

## 8. Weryfikacja: co naprawdę jest testowane

- **Symulowane są netlisty po syntezie, a nie modele RTL.** Zbliża to test do sign-offu, ale debugowanie odbywa się na spłaszczonej sieczce bramek.
- **Synteza celowo mapuje na bramki `AND/OR/XOR`** (`abc -g`). To wymóg dydaktyczny („pokaż bramki”), a nie optymalizacja.
- **Test jest cykliczny.** `expected_data` zgadza się w 100% z netlistą ALU, więc najpewniej z niej pochodzi. Świadczy o tym zamysł usuniętego generatora `testbench_do_pliku_txt.sv`, który porównywał model z netlistą i drukował gotowe linie `.vh`. Test weryfikuje więc transport SPI i wyrównanie bitów, a poprawności obliczeń ALU nie sprawdza wcale. Błąd w ALU przeszedłby niezauważony, jeśli wektory wygenerowano po nim.

---

## 9. Testbench: dane jako kod i zdarzenia

- **Wektory są kodem.** Plik `.vh` to kod proceduralny wklejany przez `` `include `` do bloku `initial`. Każdy wektor kończy się `@(next_data)`, więc kolejność testu wyznacza sama struktura pliku.
- **Synchronizacja przez nazwane zdarzenia** (`next_data`, `check_data`, `end_simulation`) działa jak prosty handshake: wystaw → czekaj na koniec ramki → porównaj na ↓clk → następny.
- **`send_request` ma dwóch „właścicieli”:** blok `always` na ↑clk oraz sam plik `.vh` (pierwsza linia `send_request = 1;`).
- **Kosmiczny timescale.** `` `timescale 1s/1ms `` z półokresem 10 daje zegar o okresie 20 s, a pełna symulacja 553 transferów trwa ~8 dni czasu symulowanego. Na wynik to nie wpływa.

---

## 10. Drobiazgi bez wpływu na działanie

- **Ostatni bit MOSI to echo MISO.** Po ↓#29 master wystawia na MOSI bit, który sam wcześniej odebrał z MISO i wsunął do rejestru. Nikt go nie czyta.
- **Martwe przypisania w stanie `SS`.** Ustawienia `sout_wrt`/`watchdog_we` nic nie robią, bo w `SS` nie ma zbocza SCLK. Działa dopiero to samo w `LOAD`.
- **Licznik slave'a jest ładowany raz na ramkę** (w `READY`), a pola B i OP obsługuje jego auto-przeładowanie z rejestru `s_cycles`. Tryb „`s_cycles = 0` = licznik wyłączony” nigdy nie jest używany.
- **Przepustowość jest niska.** Ramka trwa 61 taktów `i_clk` na 28 bitów, czyli ~0,46 bitu/takt, Po stronie MOSI użytecznych jest 20 z 28 bitów, a po stronie MISO tylko 12 (reszta to 16 zer wypełnienia).
- **„Zmiana nazwy” modułu w Yosysie idzie przez `copy` + `select -del` + `delete`** zamiast `rename`.
- **Kopie `watchdog.sv` się różnią.** Kopia mastera ma `always_ff`, a kopia slave'a zwykłe `always`, co jest śladem kopiowania plików w różnych momentach.
- **`i_rst` jest aktywny stanem niskim** mimo nazwy bez `_n`. Moduły pomocnicze nazywają ten sam sygnał poprawnie `i_rst_n`.
