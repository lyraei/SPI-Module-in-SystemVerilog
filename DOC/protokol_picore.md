# Protokół PiCoRe: jak działa

**PiCoRe** (*Pipelined Command/Response*) to synchroniczny, full-duplex interfejs szeregowy. Master wysyła ramkę-polecenie i jednocześnie odbiera ramkę-odpowiedź na **poprzednie** polecenie. Nazwy linii są zapożyczone z SPI, ale timing i format ramki są własne.

## 1. Sygnały magistrali

| Sygnał | Kierunek | Master (port) | Slave (port) | Opis |
|---|---|---|---|---|
| SCLK | master → slave | `o_sclk` | `i_sclk` | Zegar transmisji. W spoczynku `0` (CPOL=0). Okres = 2 × okres `i_clk` |
| MOSI | master → slave | `o_mosi` | `i_mosi` | Dane do slave'a, MSB first. Zmieniane na **opadającym** zboczu SCLK |
| MISO | slave → master | `i_miso` | `o_miso` | Dane do mastera, MSB first. Slave zmienia je na **narastającym** zboczu SCLK |
| SS / CS | master → slave | `o_ss` | `i_cs` | Wybór slave'a, aktywny stanem niskim |
| RST | wspólny | `i_rst` | `i_rst` | Reset asynchroniczny, **aktywny stanem niskim** (mimo nazwy `i_rst`) |

Slave próbkuje MOSI na narastającym zboczu, co przypomina **tryb 0 SPI (CPOL=0, CPHA=0)**. Są jednak dwie różnice, przez które PiCoRe nie jest zgodny z urządzeniami SPI:

1. Pierwszy bit nie leży na MOSI w chwili opadnięcia SS. Pojawia się dopiero po pierwszym opadającym zboczu SCLK, więc pierwsze narastające zbocze jest „puste” (patrz §4).
2. Slave zmienia MISO na tym samym zboczu, na którym master je próbkuje. W standardzie trybu 0 slave wystawia dane na zboczu opadającym.

## 2. Interfejs równoległy mastera (strona użytkownika)

| Port | Kier. | Szer. | Opis |
|---|---|---|---|
| `i_clk` | in | 1 | Zegar systemowy |
| `i_rst` | in | 1 | Reset asynchroniczny, aktywny `0` |
| `i_data` | in | 28 | Słowo do wysłania. Wpisywane do rejestru przesuwnego na 1. zboczu SCLK, potem może się zmieniać |
| `i_send` | in | 1 | Żądanie transmisji, sprawdzane w stanie `READY`. Sygnał poziomowy: trzymany w `1` wywołuje transfery jeden po drugim |
| `o_data` | out | 28 | Odebrane słowo. Ważne dopiero po opadnięciu `o_busy`, bo w trakcie transferu zmienia się bit po bicie |
| `o_busy` | out | 1 | `1` od stanu `SS` do `END` włącznie |

**Protokół użytkownika:** ustaw `i_data`, podnieś `i_send` na ≥1 takt `i_clk` (gdy `o_busy=0`), poczekaj aż `o_busy` spadnie do `0`, odczytaj `o_data`.

## 3. Format ramki

Ramka ma zawsze **28 bitów**, wysyłanych od bitu 27 (MSB).

### MOSI: polecenie dla ALU

```
 bit:  27 26 25 24 23 22 21 20 | 19 | 18 17 16 15 14 13 12 11 | 10 |  9  8  7  6 |  5  4  3  2  1  0
       A7 A6 A5 A4 A3 A2 A1 A0 |  x | B7 B6 B5 B4 B3 B2 B1 B0 |  x | P3 P2 P1 P0 |  x  x  x  x  x  x
       └────── argument A ─────┘      └────── argument B ─────┘      └── opcode ─┘
```

- `A = send_data[27:20]`, `B = send_data[18:11]`, `OPCODE = send_data[9:6]`.
- Bity 19, 10 i 5..0 są ignorowane przez slave'a. W wektorach testowych mają wartość `0`.
- Przerwy na bitach 19 i 10 wynikają z tego, że licznik `watchdog` w slave'ie ma okres 9, a nie 8 zboczy. Co 9. bit „wpada” w cykl przeładowania licznika i jest gubiony (§4.3).

### MISO: odpowiedź (wynik poprzedniej ramki)

```
 bit:  27 ... 20 | 19 18 17 16 | 15 ... 0
       R7 ... R0 | F3 F2 F1 F0 |  0 ... 0
       └ wynik ┘   └─ flagi ─┘
```

- `wynik = o_data[27:20]`, `flaga[i] = o_data[16+i]`, `o_data[15:0] = 0`.
- Znaczenie flag: F0 = `R[7]`, F1 = `R==0xFF`, F2 = parzysta liczba jedynek, F3 = R one-hot ([exe_unit_alu.md](exe_unit_alu.md#flagi)).

## 4. Przebieg jednej ramki zbocze po zboczu

### 4.1 Master: stany i sygnały (liczone w taktach `i_clk`)

Zmiany stanu następują na narastającym zboczu `i_clk`. SCLK, SS i BUSY są dekodowane kombinacyjnie ze stanu, więc zmieniają się tuż po tym zboczu.

```
takt i_clk  :  0     1     2     3     4     5     6    ...   56    57    58    59    60    61
stan        : READY  SS   LOAD  LOW  HIGH   LOW  HIGH   ...  HIGH   LOW  HIGH   LOW   END  READY
o_ss        :  1     0     0     0     0     0     0    ...    0     0     0     0     1     1
o_busy      :  0     1     1     1     1     1     1    ...    1     1     1     1     1     0
o_sclk      :  0     0   ┌─1─┐   0   ┌─1─┐   0   ┌─1    ...  ─1─┐   0   ┌─1─┐   0     0     0
               ────────────┘   └─────┘   └─────┘            └─────┘   └─────────────────
zbocze ↑    :             #1          #2          #3     ...  #28         #29
zbocze ↓    :                   #1          #2          ...        #28         #29
o_mosi      :  0     0     0    d27   d27   d26   d26   ...    d1    d0    d0    x
```

- `i_send=1` w `READY` → `SS` (SS opada, SCLK=0).
- `SS` → `LOAD`: SCLK rośnie (**zbocze ↑#1**). Master wpisuje `i_data` do rejestru przesuwnego i ładuje swój licznik wartością 28.
- Dalej naprzemiennie `LOW` (SCLK=0) i `HIGH` (SCLK=1). Na każdym ↑ licznik mastera zmniejsza się o 1.
- Po ↑#29 licznik mastera osiąga 0. W najbliższym `LOW` flaga `o_inter` przełącza FSM do `END` (SS=1), a potem do `READY` (BUSY=0).
- **Razem: 29 zboczy narastających SCLK, 59 taktów z aktywnym SS, 61 taktów od `i_send` do `BUSY=0`.**

### 4.2 MOSI

- MOSI jest rejestrem taktowanym **opadającym** zboczem SCLK: `o_mosi <= MSB rejestru przesuwnego`.
- Po ↓#1 na MOSI jest `d27`. Po ↑#2 rejestr przesuwa się, więc po ↓#2 jest `d26` itd.
- Po ↓#28 jest `d0`. Po ↓#29 wychodzi bit wsunięty z MISO, którego slave i tak nie czyta.
- Slave próbkuje MOSI na **narastającym** zboczu, więc na ↑#k (k = 2..29) widzi bit `d[29-k]`. **Na ↑#1 MOSI nie niesie jeszcze danych.**

### 4.3 Slave: co dzieje się na każdym zboczu ↑

| Zbocze ↑ | Bit MOSI | Stan przed → po | Licznik (watchdog) | Akcja |
|---|---|---|---|---|
| #1 | — (śmieć) | `READY → LOAD_A` (bo `i_cs=0`) | ← 8 | start ramki; `shift_out` przesuwa się (wysyła na MISO bit wyniku) |
| #2 … #9 | d27 … d20 | `LOAD_A` | 7 … 0 | `shift_in` zbiera 8 bitów A |
| #10 | d19 (gubiony) | `LOAD_A → LOAD_B` | 0 → przeładowanie 8 | `A ← shift_in` |
| #11 … #18 | d18 … d11 | `LOAD_B` | 7 … 0 | zbieranie B |
| #19 | d10 (gubiony) | `LOAD_B → LOAD_OPER` | → 8 | `B ← shift_in` |
| #20 … #27 | d9 … d2 | `LOAD_OPER` | 7 … 0 | zbieranie bajtu operacji |
| #28 | d1 (gubiony) | `LOAD_OPER → STORE_RESULT` | → 8 | `OPER ← shift_in` (= d9..d2); ALU dostaje `OPER[7:4]` = d9..d6 |
| #29 | d0 (gubiony) | `STORE_RESULT → READY` | — | `shift_out ← {wynik, flagi, 16'b0}` |

Licznik ładowany wartością 8 zgłasza `o_inter` dopiero, gdy stoi na 0, i dopiero na **następnym** zboczu przeładowuje się. Okres wynosi więc 9 zboczy, z czego 8 niesie bity pola, a 9. jest tracony. Stąd przerwy w formacie ramki.

To, że master generuje 29 zboczy (a nie 28), jest tu kluczowe. Bez ↑#29 slave nigdy nie wpisałby wyniku do rejestru wyjściowego.

### 4.4 MISO i odbiór w masterze

- Slave: `o_miso = shift_out[27]`, a `shift_out` przesuwa się na każdym ↑ w stanach innych niż `READY` (oraz w `READY` przy `i_cs=0`, czyli na ↑#1).
- Master: rejestr `s_bit_in` próbkuje `i_miso` na ↑ (wartość sprzed zbocza, bo slave zmienia MISO na tym samym zboczu). Rejestr przesuwny mastera na ↑#2 … ↑#29 wsuwa `s_bit_in`, czyli wartości MISO widziane na ↑#1 … ↑#28.
- Przed ↑#1 MISO = bit 27 słowa wpisanego do `shift_out` na ↑#29 **poprzedniej** ramki. Po 28 przesunięciach `o_data` zawiera dokładnie to słowo: `{wynik, flagi, 16'b0}`.

Dodatkowy rejestr `s_bit_in` i przesunięcie o jedno zbocze kompensują się nawzajem, więc wynik jest wyrównany do MSB.

## 5. Potok: wynik przychodzi w następnej ramce

```
ramka k   : MOSI = {A_k, B_k, OP_k}      MISO = wynik(A_{k-1}, B_{k-1}, OP_{k-1})
ramka k+1 : MOSI = {A_k+1, ...}          MISO = wynik(A_k, B_k, OP_k)
```

Wynik jest obliczany i ładowany do rejestru wyjściowego na ostatnim (29.) zboczu ramki k, a wysuwany w ramce k+1. Konsekwencje:

- Pierwsza ramka po resecie zwraca same zera, łącznie z flagami, bo `shift_out` jest zerowany resetem.
- Aby odczytać wynik ostatniej operacji, trzeba wysłać jeszcze jedną ramkę, np. same zera.

## 6. Przykład

Operacja `0` (A−B), A=5, B=3:

```
ramka k   MOSI: 00000101 0 00000011 0 0000 000000   = 28'h0501800
ramka k+1 MOSI: (cokolwiek, np. następne polecenie)
          MISO: 00000010 1000 0000000000000000       wynik = 2, flagi F3..F0 = 1000
```

Flagi:

| Flaga | Port | Wartość | Dlaczego |
|---|---|---|---|
| F0 | `SF` | 0 | bit 7 wyniku = 0 |
| F1 | `OF` | 0 | wynik ≠ 0xFF |
| F2 | `NF` | 0 | wynik 2 = 0b00000010 ma nieparzystą liczbę jedynek |
| F3 | `BF` | 1 | wynik ma dokładnie jedną jedynkę |

## 7. Ograniczenia interfejsu (skrót)

- Master nie obsługuje wielu slave'ów (jedno SS), a MISO slave'a nie jest trójstanowe.
- Slave nie resetuje się przy podniesieniu SS. Przerwana ramka rozsynchronizowuje go aż do resetu.
- SCLK powstaje kombinacyjnie ze stanu FSM (ryzyko glitchy), a MISO jest zmieniane i próbkowane na tym samym zboczu.
- Długość ramki (28) i format pól są na sztywno w kodzie slave'a.

Dlaczego to wszystko w ogóle działa: [dziwactwa.md](dziwactwa.md).

Szczegóły i propozycje poprawek: [README, sekcja A](../README.md#a-architektura--protokół-picore).
