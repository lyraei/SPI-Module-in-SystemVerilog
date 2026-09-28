# PiCoRe v2: przestrzeń projektowa

**Status: szkic, bez decyzji.** Ten dokument zbiera wszystkie poprawki potrzebne do wersji 2 oraz wszystkie pomysły na rozwój protokołu. Pomysły są opisane jako **możliwości** do wyboru. Żaden wariant nie jest jeszcze przyjęty, a wiele z nich się wyklucza albo od siebie zależy (patrz [§13](#13-zależności-i-konflikty) i [§14](#14-otwarte-decyzje)).

Każdy punkt ma identyfikator z prefiksem działu (`R` ramka, `T` timing, `I` integralność, `FL` flagi, `X` wykonanie, `K` polecenia, `RG` rejestry, `O` operacje ALU, `L` poprawki ALU, `S` sygnalizacja, `N` topologie, `V` weryfikacja), żeby dało się o nim dyskutować i później oznaczyć jako przyjęty lub odrzucony. Identyfikatory `A3`, `D2` itd. odnoszą się do [listy napraw w README](../README.md#lista-napraw-i-ulepszeń).

## Zasada nadrzędna

Każda zmiana ma dalej pasować do nazwy:

- **Pi**pelined: odpowiedź płynie z opóźnieniem, a łącze nie czeka na wynik;
- **Co**mmand: master wysyła polecenia;
- **Re**sponse: slave odsyła ramki odpowiedzi.

Pomysł, który usuwa potok albo zamienia łącze w zwykły transfer rejestrów, jest poza zakresem v2.

## Spis treści

1. [Punkt wyjścia (v1)](#1-punkt-wyjścia-v1)
2. [Poprawki bazowe](#2-poprawki-bazowe)
3. [Długość i układ ramki](#3-długość-i-układ-ramki)
4. [Warstwa fizyczna i timing](#4-warstwa-fizyczna-i-timing)
5. [Pola sterujące i integralność](#5-pola-sterujące-i-integralność)
6. [Flagi](#6-flagi)
7. [Model wykonania i potok](#7-model-wykonania-i-potok)
8. [Polecenia i rejestry](#8-polecenia-i-rejestry)
9. [Operacje ALU](#9-operacje-alu)
10. [Sygnalizacja od slave'a](#10-sygnalizacja-od-slavea)
11. [Topologie](#11-topologie)
12. [Diagnostyka, testy i narzędzia](#12-diagnostyka-testy-i-narzędzia)
13. [Zależności i konflikty](#13-zależności-i-konflikty)
14. [Otwarte decyzje](#14-otwarte-decyzje)

---

## 1. Punkt wyjścia (v1)

Stan obecny, szczegółowo opisany w [protokol_picore.md](protokol_picore.md) i [dziwactwa.md](dziwactwa.md):

| Cecha | v1 |
|---|---|
| Ramka | 28 bitów, MSB first, 29 zboczy SCLK |
| MOSI | `A[8] x B[8] x OP[4] xxxxxx`, czyli 20 użytecznych bitów z 28 |
| MISO | `R[8] F[4] 16'b0`, czyli 12 użytecznych bitów z 28 |
| Potok | stały, głębokość 1: odpowiedź w ramce k+1 |
| Integralność | brak |
| Identyfikacja odpowiedzi | brak, kolejność wynika z pozycji ramki |
| Flagi | 4, liczone z samego wyniku, nazwy nie zgadzają się z działaniem |
| ALU | 12 operacji, netlista bez źródeł |
| Slave | taktowany wyłącznie przez SCLK |

Długość 28 bitów nie jest wyborem projektowym. Wynika z dwóch off-by-one'ów, które się znoszą (28 = 1 + 3·9, a 29. zbocze dokłada błąd licznika mastera). Dlatego żadna nowa ramka nie zadziała bez poprawek z §2.

---

## 2. Poprawki bazowe

Te zmiany są potrzebne **niezależnie od wybranego wariantu** v2. Punkty z grupy „timing” trzeba zrobić w pakiecie, bo naprawienie jednego licznika albo jednego zbocza rozsypuje ramkę ([dziwactwa.md §1](dziwactwa.md#1-dwa-off-by-oney-które-się-znoszą)).

### 2.1 Timing i protokół

| ID | Poprawka | Opis |
|---|---|---|
| A3 | Licznik bez off-by-one | `watchdog` liczy `i_cycles…0` włącznie, więc okres wynosi `i_cycles+1`. Po poprawce znikają martwe bity 19 i 10 oraz sufiks `000000` |
| A4 | Dokładnie N zboczy na N bitów | Pierwszy bit leży na MOSI już przy opadnięciu SEL (preload). Znika fantomowe pierwsze zbocze. Slave potrzebuje wtedy innego momentu na wpis wyniku (własny zegar, zbocze SEL albo ostatnie zbocze ramki) |
| A5 | Zmiana i próbkowanie na przeciwnych zboczach | Slave wystawia MISO na ↓, master próbkuje na ↑. Znika rejestr `s_bit_in` i ryzyko naruszenia hold |
| A6 | Master w jednej domenie zegarowej | SCLK z przerzutnika, cała logika na `i_clk` z sygnałami strobe. SCLK, SS i BUSY przestają być dekodowaniem stanu, więc znikają glitche |
| A7 | Resynchronizacja na SEL | Nieaktywny SEL zeruje FSM, liczniki i rejestry przesuwne slave'a. Przerwana ramka przestaje rozsynchronizowywać łącze do resetu |
| A8 | Jawna ważność odpowiedzi | Odpowiedź sygnalizuje, czy niesie dane (bit VALID albo pole STATUS, patrz §5) |
| A9 | Parametryzacja | Długość ramki, kolejność bitów, CPOL/CPHA jako parametry, a nie stałe rozsiane po kodzie |
| A1, A2 | Gotowość na wiele slave'ów | Osobne linie SEL i trójstanowe MISO. Potrzebne tylko przy topologii z §11 |

### 2.2 Slave (`picore_slave.sv`)

| ID | Poprawka | Opis |
|---|---|---|
| D1 | `result_enable` | Niezadeklarowany i nieużywany. Usunąć, dodać `` `default_nettype none `` |
| D2 | 5 latchy | `s_result`, `s_flags`, `s_*_next`. Rejestry ładowane wprost z `s_data_next`, `always_comb` z wartościami domyślnymi |
| D3 | Niepodłączone wejścia | `shift_in.i_data`, `shift_out.i_bit`: tie-off `1'b0` |
| D4 | Twarde szerokości | `{16{1'b0}}`, `s_cycles = 8`, `watchdog #(.N(4))` wyliczane z parametrów |
| D5 | Martwy kod | `s_wrt_in`, powtórzone przypisania domyślne, zakomentowane `s_bit`, 8-bitowe `s_oper` przy 4 używanych bitach |

### 2.3 Master (`picore_master.sv`)

| ID | Poprawka | Opis |
|---|---|---|
| E2 | Szerokość `i_cycles` | Jawne rzutowanie zamiast ostrzeżenia Yosysa o obcięciu 32→6 bitów |
| E3 | Martwe sygnały | `s_sin_en`, `s_sin_wrt`, `SLAVES_NUMBER`, bezskuteczne przypisania w `STATE_SS` |
| E4 | Stabilne `o_data` | Rejestr wyjściowy plus impuls `o_done` zamiast „żywej” zawartości shiftera |
| E5 | Semantyka `i_send` | Udokumentować poziomowe działanie albo reagować na zbocze |

### 2.4 Bloki pomocnicze

| ID | Poprawka | Opis |
|---|---|---|
| F1 | Jawne obcięcie | `{s_shifter[N-2:0], i_bit}` zamiast niejawnego N+1→N |
| F2 | Nazwa `watchdog` | Zmienić na `bit_counter`, bo to przeładowywany licznik bitów |
| F3 | Spójny styl | Wszędzie `always_ff` / `always_comb` |
| F4 | Spójny reset | Jedna konwencja nazw (`i_rst_n`) dla sygnału aktywnego stanem niskim |
| B5 | Jedna kopia | `shifter` i `bit_counter` w `MODEL/COMMON/` |

### 2.5 Build

| ID | Poprawka | Opis |
|---|---|---|
| B1 | Katalogi | `mkdir -p ../DOC ../RTL` w Makefile albo usunięcie `write_json` |
| B2 | Zależność `sim` → `rtl` | Świeży klon ma pusty `RTL/` |
| B3 | Makefile | `.PHONY`, `clean` zamiast `clear`, cel symulacji modeli przed syntezą |
| B4 | Skrypty `.ys` | `rename` zamiast `copy`/`delete`, `synth -flatten -top X` w obu skryptach |
| B6 | Źródło ALU | Behawioralne RTL według [exe_unit_alu.md](exe_unit_alu.md), zweryfikowane przeciw starej netliście na wszystkich 1 048 576 kombinacjach |

### 2.6 Testbench

| ID | Poprawka | Opis |
|---|---|---|
| C2 | Wyścigi | Jeden proces sterujący (task transferu), przypisania nieblokujące |
| C3 | Model referencyjny | Losowe polecenia, oczekiwana odpowiedź liczona w locie z uwzględnieniem potoku. Dziś test sprawdza transport, a poprawności ALU nie |
| C4 | Drobiazgi | `%b` zamiast `%21b`, `` `timescale 1ns/1ps ``, usunięcie nieużywanych makr |
| C6 | Testy protokołu | Asercje SVA, przerwana ramka, reset w trakcie transferu |

### 2.7 Repozytorium i nazwy

| ID | Poprawka | Opis |
|---|---|---|
| G1 | CI | GitHub Actions: `make rtl sim`, fail przy dowolnym błędnym transferze |
| G2 | Lint | Verilator `--lint-only -Wall` |
| G4 | Konwencja komentarzy | Jeden język i jedna konwencja znaków diakrytycznych |
| — | Etap 0 roadmapy | Moduły `spi_*` → `picore_*`, sygnały testbencha, plik wektorów ([roadmap.md](roadmap.md#etap-0-porządek-w-nazwach)) |

### 2.8 Poprawki ALU i flag

Obecne zachowanie ALU jest w pełni opisane, ale kilka przypadków jest ewidentnie błędnych. Poprawki zmieniają wyniki, więc stare wektory przestaną pasować. Tryb zgodności opisuje [FL9](#fl9-tryb-zgodności-legacy-flags).

| ID | Operacja | Problem | Poprawka |
|---|---|---|---|
| L1 | op 8, liczba zer w `{A,B}` | Liczone modulo 16, `A=B=0` daje 0 | Wyjście 5-bitowe, wynik 16 |
| L2 | op 11, indeks najstarszej jedynki | `A=0` daje 7, czyli wynik nieodróżnialny od `A=0x80` | Wynik 0 plus flaga Z lub E |
| L3 | op 7, indeks najmłodszej jedynki | `A=0` daje 0, czyli tyle samo co `A=1` | Jak L2 |
| L4 | op 5/6, „CRC” | Obcięte mnożenie wielomianów na 3 bitach, bez dzielenia | Prawdziwy krok CRC-8 (patrz [O10](#9-operacje-alu)) |
| L5 | op 9/10, U2↔ZM | „−0” (`128`) mapowane różnie w obie strony | Ustalić jedną konwencję i flagę dla wartości niereprezentowalnej |
| L6 | Nazwy flag | `OF` to `R==0xFF`, `NF` to parzystość, `BF` to one-hot | Nazwy zgodne z działaniem albo nowy zestaw z §6 |

---

## 3. Długość i układ ramki

Każdy wariant zakłada poprawki A3/A4, czyli dokładnie N zboczy na N bitów i brak martwych bitów.

### R1. Ramka zwarta, 20 bitów

```
MOSI:  A[7:0] | B[7:0] | OP[3:0]
MISO:  R[7:0] | F[3:0] | wolne[7:0]
```

Minimalna zmiana względem v1: te same pola, bez martwych bitów. 8 wolnych bitów odpowiedzi może zmieścić TAG i VALID.

- Plusy: najmniej pracy, stare wektory da się przeliczyć 1:1.
- Minusy: brak miejsca na integralność i sterowanie po stronie polecenia, 20 bitów nie jest wielokrotnością bajtu.

### R2. Jedno słowo 32 bity

```
MOSI:
 31      24 23      16 15     11 10    8 7      4 3    0
  A[7:0]     B[7:0]     OP[4:0]  TAG[2:0] MODE[3:0] CRC4

MISO (odpowiedź na polecenie k−1):
 31            16 15       8 7     5 4     3    0
   R[15:0]         FLAGS[7:0] TAG[2:0] VALID CRC4
```

- **OP 5 bitów:** 32 operacje.
- **TAG 3 bity:** odpowiedź mówi, na które polecenie odpowiada (§5).
- **MODE 4 bity:** modyfikatory wykonania, np. `SRC_A`, `SRC_B`, `SIGNED`, `SAT` (§7).
- **R 16 bitów:** mieści wynik MUL 8×8.
- **FLAGS 8 bitów:** zestaw z §6.
- **CRC-4** po obu stronach.

Plusy: 4 bajty, więc sterownik na MCU operuje na `uint32_t`. Przy czystym timingu ramkę da się wysłać sprzętowym SPI (patrz [T1](#t1-zgodność-z-spi-mode-0)).

Minusy: pola są ciasno upakowane. Każdy dodatkowy pomysł (pokwitowanie, głowa na żywo, dłuższy TAG) wymaga zabrania bitów innemu polu. Warianty upakowania MISO:

| Wariant | Układ | Kosztem czego |
|---|---|---|
| R2a | `R16 F8 TAG3 VALID1 CRC4` | bazowy |
| R2b | `R16 F8 TAG3 VALID1 DIG4` | CRC odpowiedzi zastąpione skrótem polecenia ([I5](#i5-pokwitowanie-polecenia)) |
| R2c | `NOW4 R16 F8 TAG3 VALID1` | CRC zastąpione stanem na żywo ([S2](#s2-ramka-dzielona-głowa-na-żywo)) |
| R2d | `R8 F8 TAG4 STAT4 DIG4 CRC4` | wynik 8-bitowy, za to wszystkie pola sterujące |

### R3. Dwa słowa, 64 bity

```
MOSI:  A[15:0] | B[15:0] | OP[5:0] | TAG[3:0] | MODE[5:0] | rez[7:0] | CRC8
MISO:  R[31:0] | FLAGS[7:0] | TAG[3:0] | STAT[3:0] | DIG[7:0] | CRC8
```

16-bitowe argumenty, 32-bitowy wynik, pełne CRC-8 i miejsce na wszystkie pola sterujące naraz.

- Plusy: brak kompromisów w upakowaniu, łatwe dołożenie kolejnych pól.
- Minusy: dwa razy dłuższa ramka przy tych samych prostych operacjach, większe ALU (16-bitowe mnożenie).

### R4. Nagłówek plus ładunek o zmiennej długości

Wariant z [roadmapy, etap 2](roadmap.md#etap-2-picore-v1-czyli-prawdziwy-protokół):

```
polecenie:  CMD[7:0] | TAG[3:0] | LEN[3:0] | PAYLOAD[LEN bajtów] | CRC8
odpowiedź:  STATUS[7:0] | TAG[3:0] | LEN[3:0] | PAYLOAD | CRC8
```

Polecenie nie musi być operacją ALU. Ta sama ramka obsługuje odczyt rejestrów, zapis konfiguracji, ładowanie mikroprogramu itd.

- Plusy: protokół przeżywa zmianę slave'a (ALU, GPIO, timer), bo ramka nie jest skrojona pod jedno urządzenie.
- Minusy: zmienna długość komplikuje potok (odpowiedź k+1 może mieć inną długość niż polecenie k+1), FSM slave'a musi parsować nagłówek.

### R5. Długość jako parametr

Stała długość, ale wybierana parametrem syntezy (`BITS = 20/32/64`), z polami wyliczanymi z parametrów. Nie wyklucza R1–R3, raczej łączy je w jedną implementację.

### Porównanie

| | R1 | R2 | R3 | R4 |
|---|---|---|---|---|
| Bity polecenia | 20 | 32 | 64 | 24 + 8·LEN |
| Użyteczne bity MOSI | 20 | 21 + 4 MODE | 38 + 6 MODE | zależne od LEN |
| Wynik | 8 | 16 | 32 | zależny od LEN |
| Integralność | brak | CRC-4 | CRC-8 | CRC-8 |
| TAG | opcjonalnie w odpowiedzi | 3 bity | 4 bity | 4 bity |
| Zgodność z bajtami | nie | tak | tak | tak |
| Złożoność | niska | średnia | średnia | wysoka |

---

## 4. Warstwa fizyczna i timing

### T1. Zgodność z SPI mode 0

Po poprawkach A4/A5 i przy ramce będącej wielokrotnością bajtu (R2, R3, R4) PiCoRe staje się elektrycznie zgodny z SPI mode 0 (CPOL=0, CPHA=0). Master można wtedy zrealizować sprzętowym SPI dowolnego mikrokontrolera.

Konsekwencja: odrębność PiCoRe przenosi się wyłącznie na warstwę ramki (potok, TAG, forwarding). Argument „to nie jest SPI” przestaje dotyczyć przebiegów.

### T2. Własny timing

Świadome odejście od SPI, np. inny moment próbkowania, preambuła albo stan synchronizacji. Zachowuje odrębność elektryczną, ale wyklucza sprzętowe SPI po stronie mastera.

### T3. Nazwy linii

| Opcja | Linie |
|---|---|
| jak w SPI | `SCLK`, `MOSI`, `MISO`, `SS` |
| własne | `PCLK`, `CMD` (master→slave), `RSP` (slave→master), `SEL_n` |

Własne nazwy mówią wprost, że to osobny protokół. Nazwy SPI są czytelne dla każdego.

### T4. Dzielnik SCLK

Parametr `SCLK = i_clk / 2k` zamiast sztywnego `/2`. Wymaga A6.

### T5. Slave z własnym zegarem

Dziś slave działa tylko wtedy, gdy master generuje SCLK. Własny zegar z synchronizatorami (CDC) pozwala liczyć operacje wielotaktowe między ramkami i rozwiązuje problem momentu wpisu wyniku z A4.

### T6. DDR

Dane na obu zboczach zegara. Dwukrotnie większa przepustowość przy tym samym zegarze, ale ciaśniejsze wymagania czasowe.

### T7. Wiele linii danych (x2, x4)

Na wzór QSPI. Szerokość negocjowana przez rejestr `CONFIG`, a start zawsze w trybie x1.

### T8. Auto-kalibracja próbkowania

Master przy wyższych częstotliwościach dobiera opóźnienie próbkowania MISO, np. wysyłając polecenie echa ze znanym wzorcem.

### T9. Kolejność bitów

MSB first (jak dziś) albo LSB first jako parametr (A9).

---

## 5. Pola sterujące i integralność

### I1. TAG

Kilkubitowy identyfikator polecenia, powtarzany w odpowiedzi. Potok staje się jawny: master nie musi liczyć ramek, żeby wiedzieć, czyj to wynik. Przy potoku głębokości 1 wystarczają 2–3 bity, przy głębszym potoku i odpowiedziach poza kolejnością (X6, X7) potrzeba więcej.

### I2. VALID / STATUS

Minimum to jeden bit VALID: odpowiedź niesie wynik. Rozszerzona wersja to pole STATUS:

| Bit | Znaczenie |
|---|---|
| `VALID` | odpowiedź niesie dane |
| `ERR_CMD` | nieznane polecenie lub opcode |
| `ERR_CRC` | polecenie przyszło uszkodzone |
| `BUSY` | wynik jeszcze się liczy |
| `FULL` | kolejka poleceń pełna (X8) |

### I3. Kontrola integralności

| Opcja | Koszt | Wykrywa |
|---|---|---|
| bit parzystości | 1 bit | pojedyncze błędy |
| CRC-4 (x⁴+x+1) | 4 bity | wszystkie błędy 1- i 2-bitowe w krótkiej ramce, paczki do 4 bitów |
| CRC-8 (np. 0x07) | 8 bitów | jak wyżej, dla dłuższych ramek |
| brak | 0 | nic |

CRC w protokole zastępuje przy okazji fałszywe „CRC” z opcode'ów 5/6.

### I4. Bit przełączany (toggle)

Master przełącza jeden bit przy każdym **nowym** poleceniu, jak DATA0/DATA1 w USB. Jeśli master powtarza ramkę po błędzie, bit się nie zmienia, więc slave wie, że to duplikat, i nie wykonuje go drugi raz. Daje idempotencję za 1 bit.

### I5. Pokwitowanie polecenia

Odpowiedź k niesie oprócz wyniku krótki skrót (np. CRC-4) polecenia k−1 **w postaci, w jakiej slave je odebrał**. Master porównuje go ze skrótem tego, co wysłał. Wykrywa to błąd na linii polecenia nawet wtedy, gdy slave go nie zauważył, i potwierdza, że wynik dotyczy właściwego polecenia.

### I6. Licznik sekwencji

Slave numeruje odpowiedzi (np. 3 bity modulo 8). Luka w numeracji oznacza zgubioną ramkę. Częściowo pokrywa się z TAG-iem, więc zwykle wystarczy jedno z nich.

### I7. Słowo synchronizacji

Stały wzorzec na początku ramki (albo co N ramek w trybie burst, X10). Pozwala slave'owi odzyskać granice ramek bez udziału SEL.

---

## 6. Flagi

Obecne 4 flagi liczone są z samego wyniku, a ich nazwy nie odpowiadają działaniu. Poniżej katalog możliwych flag. Wybór zależy od liczby bitów w ramce (4 w R1, 8 w R2/R3).

### FL1. Z (zero)

`R == 0`. Najbardziej podstawowa flaga, której dziś brakuje.

### FL2. C (carry / borrow)

Przeniesienie z ADD, pożyczka z SUB, bit wysunięty przy przesunięciach. Umożliwia arytmetykę wielosłowową (ADC/SBC).

### FL3. V (overflow ze znakiem)

Przepełnienie w arytmetyce U2. Obecne `OF` oznacza tylko `R == 0xFF`.

### FL4. N (znak)

`R[msb]`. Odpowiada obecnemu `SF`.

### FL5. P (parzystość)

Parzysta liczba jedynek w R. Odpowiada obecnemu `NF`, tylko z nazwą zgodną z działaniem.

### FL6. H (half-carry)

Przeniesienie między nibble'ami. Potrzebne do poprawki BCD (DAA).

### FL7. SV (sticky overflow)

Ustawia się przy dowolnym przepełnieniu i trzyma do jawnego polecenia `CLR_FLAGS`, jak flagi wyjątków w IEEE 754. Master może wykonać serię obliczeń i sprawdzić tylko jedną ramkę na końcu.

### FL8. E (błąd)

Zbiorcza flaga błędu: zły CRC, nieznany opcode, niezgodny TAG, niereprezentowalny wynik (L2, L5). Może też żyć w polu STATUS (I2) zamiast we flagach.

### FL9. Tryb zgodności (legacy flags)

Tryb wybierany w `CONFIG`, który odtwarza obecne 4 flagi 1:1 (`R[7]`, `R==0xFF`, parzystość, one-hot). Pozwala używać starych 553 wektorów jako testu regresji transportu.

### FL10. Flagi porównania

Po operacji `CMP` flagi niosą LT/EQ/GT, osobno dla liczb ze znakiem i bez. Mogą zająć miejsce H i P, bo przy `CMP` nie mają one sensu.

### FL11. ONEHOT

Obecne `BF` (wynik ma dokładnie jedną jedynkę). Mało przydatne ogólnie, ale naturalne dla operacji bitowych.

### FL12. Maska flag

Polecenie albo rejestr wybiera, które flagi są aktualizowane (jak w niektórych DSP). Pozwala zachować C między operacjami, które go nie dotyczą.

---

## 7. Model wykonania i potok

### X1. Forwarding (`SRC_A = PREV`)

Bit w polu MODE każe slave'owi użyć jako argumentu A wyniku **poprzedniego** polecenia, który jeszcze nie dotarł do mastera. To bypass jak w potoku procesora, tyle że w protokole. Obliczenia łańcuchowe (`((a+b)*c)^d`) idą bez oczekiwania na wynik i bez odsyłania go z powrotem.

### X2. Akumulator (`SRC_B = ACC`)

Rejestr `ACC` w slave'ie, zapisywany wynikiem na żądanie. Różni się od X1 tym, że wartość przeżywa dowolnie wiele poleceń.

### X3. Modyfikatory SIGNED / SAT

Bity MODE zmieniające interpretację: arytmetyka ze znakiem, arytmetyka z nasyceniem. Zmniejszają liczbę potrzebnych opcode'ów (jedno ADD zamiast ADD, ADDS, ADD_SAT).

### X4. NOP / FLUSH

Polecenie bez pracy, które wypycha ostatnią odpowiedź z potoku. Dziś tę rolę pełni ramka samych zer, która w v1 jest przypadkiem operacją `0 − 0`.

### X5. Konfigurowalna głębokość potoku D

Odpowiedź na polecenie k przychodzi w ramce k+D, a D ustawia się w `CONFIG`. D=0 to tryb synchroniczny dla prostych hostów (wymaga T5 lub ramki z odstępem na obliczenie), D=1 to obecne zachowanie, D>1 wymaga kolejki (X8).

### X6. Operacje wielotaktowe

Mnożenie, dzielenie, pierwiastek, CORDIC. Slave odpowiada `BUSY`, a wynik przychodzi w którejś z kolejnych ramek z właściwym TAG-iem. Wymaga T5 albo liczenia na zboczach kolejnych ramek.

### X7. Odpowiedzi poza kolejnością

Szybkie polecenia nie czekają na wolne. TAG mówi, której odpowiedzi dotyczy. Wymaga I1 z odpowiednią liczbą bitów.

### X8. Kolejka poleceń (FIFO) i kredyty

Slave buforuje kilka poleceń. W STATUS podaje liczbę wolnych miejsc, więc master nie przepełni kolejki.

### X9. CANCEL

Polecenie unieważniające odpowiedź o danym TAG-u, która jeszcze nie wyszła. Ma sens tylko przy X5 z D>1 albo X6.

### X10. Tryb burst / stream

SEL trzymane nisko przez N ramek bez przerw. Granice ramek wyznacza licznik albo słowo synchronizacji (I7). Oszczędza takty na opadanie i podnoszenie SEL między ramkami.

### X11. Mikroprogram

`LOAD_PROG` zapisuje 4–8 poleceń do pamięci slave'a, a `RUN` wykonuje je z forwardingiem (X1) między krokami. Jedna ramka uruchamia całą sekwencję.

---

## 8. Polecenia i rejestry

Dotyczy głównie wariantu R4, ale część da się zmieścić w R2/R3 przez zarezerwowane opcode'y.

### Polecenia

| ID | Polecenie | Działanie |
|---|---|---|
| K1 | `EXEC` | operacja ALU (dziś jedyne polecenie) |
| K2 | `NOP` | wypchnięcie odpowiedzi (X4) |
| K3 | `READ_REG` | odczyt rejestru |
| K4 | `WRITE_REG` | zapis rejestru |
| K5 | `RESET` | reset logiczny slave'a przez łącze |
| K6 | `CLR_FLAGS` | zerowanie flag sticky (FL7) |
| K7 | `CANCEL` | unieważnienie odpowiedzi (X9) |
| K8 | `LOAD_PROG` / `RUN` | mikroprogram (X11) |
| K9 | `SELFTEST` | BIST (V1 w §12) |
| K10 | `CHALLENGE` | identyfikacja przez odpowiedź na nonce (V3 w §12) |
| K11 | `ECHO` | odpowiedź zwraca otrzymany ładunek, do testów łącza i kalibracji (T8) |

### Rejestry

| ID | Rejestr | Rola |
|---|---|---|
| RG1 | `ID` | stała, np. `0x9C`, do szybkiego testu łącza i rozpoznania typu slave'a |
| RG2 | `VERSION` | wersja protokołu i implementacji |
| RG3 | `CAPS` | bitowa lista obsługiwanych funkcji (X1, X5, T6, T7…), żeby master mógł negocjować |
| RG4 | `STATUS` | stan slave'a |
| RG5 | `CONFIG` | głębokość potoku, szerokość linii, tryb flag, tryb błędów |
| RG6 | `ACC` | akumulator (X2) |
| RG7 | `FLAGS` | flagi sticky do odczytu |

Rejestr `CAPS` pozwala mieć za tym samym protokołem różne typy slave'ów (ALU, GPIO, timer, generator losowy): master pyta o `ID` i `CAPS` i dostosowuje się.

---

## 9. Operacje ALU

Poprawki istniejących operacji są w [§2.8](#28-poprawki-alu-i-flag). Poniżej kandydaci na nowe operacje. Przy OP 4-bitowym (R1) mieści się 16 operacji, przy 5-bitowym (R2) 32, przy 6-bitowym (R3) 64.

| ID | Operacja | Uwagi |
|---|---|---|
| O1 | `ADD`, `ADC` | dziś brak dodawania, jest tylko odejmowanie |
| O2 | `SBC` | odejmowanie z pożyczką |
| O3 | `MUL` 8×8→16 | wymaga 16-bitowego wyniku (R2, R3) albo dwóch ramek |
| O4 | `CMP` | ustawia tylko flagi (FL10) |
| O5 | `MIN`, `MAX`, `ABS` | z bitem SIGNED (X3) |
| O6 | `ASR` | przesunięcie arytmetyczne; dziś jest tylko logiczne |
| O7 | `ROL`, `ROR` | rotacje |
| O8 | `POPCNT`, `CLZ`, `CTZ` | porządne wersje obecnych op 7, 8, 11 |
| O9 | `BITREV`, `BSWAP` | odwrócenie bitów, zamiana nibble'i lub bajtów |
| O10 | `CRC8_STEP` | prawdziwy krok CRC-8 (zamiast op 5/6) |
| O11 | `GF_MUL` | mnożenie w GF(2⁸) modulo 0x11B, jak w AES. Obecne op 5 to już mnożenie bez przeniesień, brakuje tylko redukcji |
| O12 | `BIN2BCD`, `BCD2BIN` | konwersje dziesiętne |
| O13 | `BIN2GRAY`, `GRAY2BIN` | kod Graya |
| O14 | `ADD_SAT`, `SUB_SAT` | albo przez bit SAT (X3) |
| O15 | `DIV`, `MOD` | wielotaktowe (X6) |
| O16 | `SQRT`, `CORDIC` | wielotaktowe (X6) |
| O17 | Obecne op 0–11 | zachowane w trybie zgodności albo zmapowane na nowe kody |

---

## 10. Sygnalizacja od slave'a

### S1. ATTN przy nieaktywnym SEL

Gdy SEL jest nieaktywne, slave może ściągnąć linię odpowiedzi do 0, żeby poprosić o obsługę (wynik gotowy, błąd, zdarzenie). Działa jak przerwanie bez piątego przewodu, podobnie jak IBI w I3C. Wymaga wyjścia open-drain albo pull-upu na linii i kłóci się z trójstanowym MISO na wspólnej magistrali (A2).

### S2. Ramka dzielona: głowa na żywo

Pierwsze bity odpowiedzi to stan slave'a próbkowany **teraz** (BUSY, FULL, ATTN, ERR), a reszta to wynik z potoku. Master już w trakcie bieżącej ramki wie, czy slave nadąża, zamiast dowiadywać się o tym ramkę później.

### S3. Wstrzykiwanie błędów

Tryb testowy w `CONFIG`, w którym slave celowo psuje co N-tą odpowiedź (zły CRC, zły TAG, BUSY). Pozwala testować obsługę błędów po stronie mastera bez zakłócania linii.

---

## 11. Topologie

### N1. Punkt-punkt

Jeden master, jeden slave. Stan obecny, najprostszy.

### N2. Gwiazda

Osobna linia SEL dla każdego slave'a, trójstanowe MISO (A1, A2). Klasyczne rozwiązanie z SPI.

### N3. Daisy-chain

Wyjście odpowiedzi jednego slave'a to wejście poleceń kolejnego. Każdy slave dokłada jedną ramkę opóźnienia, więc łańcuch sam jest potokiem. Polecenie niesie adres albo licznik przeskoków.

### N4. Adresowanie w nagłówku

Wspólna magistrala, pole `ADDR` w poleceniu, odpowiada tylko zaadresowany slave. Wymaga trójstanowego MISO.

### N5. Broadcast

Polecenie dla wszystkich slave'ów naraz, np. `RESET` albo `CONFIG`. W v1 wszystkie slave'y słyszały każdą ramkę, co było przyczyną błędu przy przełączaniu ([dziwactwa.md §5](dziwactwa.md#5-ślady-architektury-z-trzema-slaveami-i-nazwy-spi)). Jawny broadcast zamienia tę wadę w funkcję.

---

## 12. Diagnostyka, testy i narzędzia

### V1. BIST z sygnaturą MISR

Polecenie `SELFTEST` przepuszcza ALU przez wszystkie kombinacje wejść (albo przez sekwencję z LFSR) i zwraca 16-bitową sygnaturę rejestru MISR. Poprawność netlisty na FPGA sprawdza się jedną ramką, porównując sygnaturę z wartością z symulacji.

### V2. Tryb zgodności z v1

Ramka, flagi i opcode'y odtwarzające v1, żeby stare wektory służyły jako test regresji. Obejmuje FL9 i O17.

### V3. Challenge-response ID

Master wysyła nonce, slave zwraca `f(nonce)`, np. xorshift z wbudowaną stałą. Mocniejszy test łącza niż stały `ID`, bo wykrywa też slave'a, który tylko powtarza dane. Nie jest to zabezpieczenie kryptograficzne.

### V4. Model referencyjny i losowe testy

Behawioralny model ALU i protokołu w testbenchu (C3), losowe polecenia, oczekiwane odpowiedzi liczone z uwzględnieniem potoku, TAG-ów i błędów.

### V5. Weryfikacja formalna

SymbiYosys z asercjami: dokładnie N zboczy na ramkę, odpowiedź z TAG-iem k przychodzi po poleceniu k, brak utraty poleceń przy pełnej kolejce, powrót do stanu spoczynku po przerwanej ramce.

### V6. cocotb

Testbench w Pythonie zamiast wektorów w `.vh`. Ten sam model referencyjny może potem posłużyć jako sterownik po stronie PC.

### V7. Narzędzia poza HDL

Most UART/USB ↔ master PiCoRe z CLI w Pythonie, sterownik bit-bang w C na mikrokontroler (`libpicore`), przebiegi w WaveDrom w dokumentacji ([roadmap.md, etap 7](roadmap.md#etap-7-sprzęt-i-narzędzia)).

---

## 13. Zależności i konflikty

| Pomysł | Wymaga | Kłóci się z |
|---|---|---|
| wszystkie warianty R | A3, A4, A5 | — |
| T1 (zgodność z SPI) | A4, A5, ramka wielokrotnością bajtu | T2, S1 przy braku pull-upu, R1 |
| T4 (dzielnik) | A6 | — |
| T6, T7 (DDR, x2/x4) | A6, RG5 `CONFIG` | T1 przy sprzętowym SPI bez QSPI |
| X1 (forwarding) | pole MODE (R2, R3, R4) | — |
| X5 z D=0 | T5 albo odstęp między ramkami | — |
| X5 z D>1, X6, X7 | I1 (TAG), X8 | R1 bez miejsca na TAG |
| X9 (CANCEL) | X5 z D>1 albo X6 | — |
| X10 (burst) | I7 albo licznik, A7 | — |
| X11 (mikroprogram) | X1, pamięć w slave'ie, R4 lub zarezerwowany opcode | — |
| I4 (toggle) | mechanizm powtarzania po stronie mastera | — |
| I5 (pokwitowanie) | miejsce w odpowiedzi | CRC odpowiedzi w R2 (R2b) |
| S1 (ATTN) | open-drain lub pull-up | N2, N4 z trójstanowym MISO |
| S2 (głowa na żywo) | miejsce w odpowiedzi | CRC odpowiedzi w R2 (R2c) |
| O3 (MUL) | wynik ≥16 bitów | R1 |
| O15, O16 | X6 | — |
| V1 (BIST) | T5 albo liczenie przez wiele ramek | — |
| FL9, V2 (zgodność) | tryb w `CONFIG` | L1–L6 w trybie zgodności |
| N3 (daisy-chain) | adres albo licznik przeskoków w poleceniu | S1 |
| N4, N5 | A2 | S1 |

---

## 14. Otwarte decyzje

Pytania, na które trzeba odpowiedzieć przed przejściem od tego dokumentu do właściwej specyfikacji:

1. **Długość ramki:** R1, R2, R3, R4 czy parametr (R5)?
2. **Timing:** zgodność elektryczna z SPI mode 0 (T1) czy własny (T2)?
3. **Nazwy linii:** SPI czy własne (T3)?
4. **Slave:** dalej taktowany tylko przez łącze czy z własnym zegarem (T5)? Od tego zależą X5 z D=0, X6 i V1.
5. **Integralność:** parzystość, CRC-4, CRC-8 czy brak (I3)? Tylko w poleceniu, czy w obu kierunkach?
6. **Identyfikacja odpowiedzi:** TAG (I1), licznik sekwencji (I6), pokwitowanie (I5), czy ich kombinacja?
7. **Flagi:** ile bitów i który zestaw z §6? Czy zachować tryb zgodności (FL9)?
8. **Potok:** stała głębokość 1, konfigurowalna (X5), czy kolejka z odpowiedziami poza kolejnością (X7, X8)?
9. **Model polecenia:** tylko `EXEC` z modyfikatorami (R2, R3) czy pełny zestaw poleceń i rejestrów (R4, §8)?
10. **Zakres ALU:** które operacje z §9 i czy obecne op 0–11 zachowują swoje kody?
11. **Topologia docelowa:** punkt-punkt, gwiazda, daisy-chain czy magistrala adresowana (§11)?
12. **Cecha wyróżniająca:** które z X1, I5, S2, S1, X11 mają być „twarzą” PiCoRe v2?
