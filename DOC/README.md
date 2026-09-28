# Dokumentacja PiCoRe

**PiCoRe — a pipelined command/response serial link.** Synchroniczny, 4-przewodowy, full-duplex interfejs szeregowy z ramką stałej długości, łączący jednego mastera z jednym slave'em. Linie nazywają się jak w SPI (SCLK, MOSI, MISO, SS), ale protokół nie jest zgodny ze standardem SPI. Slave jest zdalnie wywoływaną jednostką arytmetyczno-logiczną (ALU). Master wysyła w jednej 28-bitowej ramce dwa 8-bitowe argumenty i 4-bitowy kod operacji. Slave liczy wynik i odsyła go (8 bitów wyniku + 4 flagi) w **następnej** ramce.

Pierwotnie w projekcie były trzy slave'y z trzema różnymi ALU napisanymi przez trzech autorów. Zostawiona jest tylko **jednostka 1**. Ślady tamtej architektury opisuje [dziwactwa.md §5](dziwactwa.md#5-ślady-architektury-z-trzema-slaveami-i-nazwy-spi).

## Spis treści

| Dokument | Zawartość |
|---|---|
| [protokol_picore.md](protokol_picore.md) | **Jak działa interfejs**: sygnały, format ramki, przebiegi czasowe zbocze po zboczu, potok (opóźnienie jednej ramki), przykład transakcji |
| [picore_master.md](picore_master.md) | `MODEL/PICORE_MASTER/picore_master.sv`: porty, parametry, FSM, ścieżki danych |
| [picore_slave.md](picore_slave.md) | `MODEL/PICORE_SLAVE/picore_slave.sv`: slave, FSM odbioru, rejestry |
| [exe_unit_alu.md](exe_unit_alu.md) | `MODEL/PICORE_SLAVE/exe_unit_1_rtl.sv`: pełna tabela operacji i flag ALU (odtworzona z netlisty) |
| [bloki_pomocnicze.md](bloki_pomocnicze.md) | `shifter.sv` i `watchdog.sv`: rejestr przesuwny i licznik |
| [synteza_i_symulacja.md](synteza_i_symulacja.md) | `WORK/makefile`, skrypty Yosysa `*.ys`, `TEST/testbench.sv`, wektory `*.vh` |
| [spec_v2.md](spec_v2.md) | **Przestrzeń projektowa PiCoRe v2**: wszystkie poprawki i pomysły na nowy protokół jako możliwości, z zależnościami i otwartymi decyzjami |
| [roadmap.md](roadmap.md) | **Plany rozwoju PiCoRe**: naprawy, rozszerzenia protokołu, pomysły hobbystyczne |
| [dziwactwa.md](dziwactwa.md) | **Nietypowe rozwiązania i dziwactwa**: dlaczego układ działa, choć wygląda, jakby nie powinien |

Lista znanych błędów i proponowanych poprawek jest w [głównym README](../README.md#lista-napraw-i-ulepszeń). Ta dokumentacja opisuje **stan obecny**, razem z jego dziwactwami.

## Architektura

```
                       TESTBENCH (TEST/testbench.sv)
 ┌──────────────────────────────────────────────────────────────────┐
 │                                                                  │
 │  send_data[27:0] ──►┌──────────────┐  o_mosi ──► i_mosi ┌──────┐ │
 │  send_request ─────►│  spi_master  │  o_sclk ──► i_sclk │slave │ │
 │  clk, rst ─────────►│              │  o_ss   ──► i_cs   │ ALU1 │ │
 │  received_data ◄────│ o_data       │                    │      │ │
 │  master_busy ◄──────│ o_busy       │  i_miso ◄── o_miso └──────┘ │
 │                     └──────────────┘                             │
 └──────────────────────────────────────────────────────────────────┘
```

- **Master** (`spi_master`) dostaje z zewnątrz 28-bitowe słowo i impuls `i_send`. Generuje SCLK (połowa częstotliwości `i_clk`) i SS, wysyła słowo przez MOSI i jednocześnie odbiera 28 bitów z MISO.
- **Slave** (`spi_exe_unit_1`) jest taktowany wyłącznie przez SCLK i nie ma własnego zegara.

Pliki i katalogi noszą nazwy PiCoRe (`picore_master.sv`, `picore_slave.sv`), ale moduły w HDL nadal nazywają się `spi_master` i `spi_exe_unit_1`, bo treść HDL nie była zmieniana.

## Katalog plików

| Plik | Rola | Dokumentacja |
|---|---|---|
| `README.md` | Opis projektu i lista napraw | — |
| `.gitignore` | Ignoruje wygenerowane netlisty `RTL/picore*` (i stare `RTL/spi*`), logi, `waves.vcd`, `signals.gtkw`, pliki `*.run` i `DOC/*.json` | — |
| `DOC/` | Ta dokumentacja. Tu Yosys zapisuje też `picore_slave.json` (plik generowany, ignorowany) | — |
| `MODEL/PICORE_MASTER/picore_master.sv` | Master PiCoRe | [picore_master.md](picore_master.md) |
| `MODEL/PICORE_MASTER/shifter.sv` | Rejestr przesuwny | [bloki_pomocnicze.md](bloki_pomocnicze.md#shifter) |
| `MODEL/PICORE_MASTER/watchdog.sv` | Licznik okresu | [bloki_pomocnicze.md](bloki_pomocnicze.md#watchdog) |
| `MODEL/PICORE_SLAVE/picore_slave.sv` | Slave (wrapper PiCoRe wokół ALU) | [picore_slave.md](picore_slave.md) |
| `MODEL/PICORE_SLAVE/exe_unit_1_rtl.sv` | Netlista ALU (moduł `exe_unit_rtl`) | [exe_unit_alu.md](exe_unit_alu.md) |
| `MODEL/PICORE_SLAVE/shifter.sv`, `watchdog.sv` | Kopie plików z `PICORE_MASTER/` | [bloki_pomocnicze.md](bloki_pomocnicze.md) |
| `RTL/.gitkeep` | Pusty katalog na netlisty generowane przez `make rtl` | [synteza_i_symulacja.md](synteza_i_symulacja.md) |
| `WORK/makefile` | Cele `rtl`, `sim`, `clear`, `wave` | [synteza_i_symulacja.md](synteza_i_symulacja.md#makefile) |
| `WORK/picore_master.ys`, `picore_slave.ys` | Skrypty syntezy Yosysa | [synteza_i_symulacja.md](synteza_i_symulacja.md#skrypty-yosysa-ys) |
| `TEST/testbench.sv` | Testbench całego systemu (na netlistach) | [synteza_i_symulacja.md](synteza_i_symulacja.md#testbench) |
| `TEST/test_spi_exe_unit_1.vh` | Wektory testowe dołączane przez `` `include `` | [synteza_i_symulacja.md](synteza_i_symulacja.md#wektory-testowe-vh) |

## Szybki start

```bash
cd WORK
make rtl     # Yosys: MODEL/* -> RTL/*_rtl.sv (netlisty AND/OR/XOR + przerzutniki)
make sim     # Icarus: RTL/*.sv + TEST/testbench.sv, wynik: liczba błędnych/poprawnych transferów
make wave    # GTKWave: WORK/waves.vcd
```

Zweryfikowany wynik (Yosys 0.69, Icarus Verilog 12.0): **553 poprawne, 0 błędnych transferów**.

## Skąd pochodzą informacje

- Porty, FSM i protokół opisano na podstawie kodu źródłowego. Przebiegi czasowe są potwierdzone symulacją (29 zboczy SCLK i 59 cykli `i_clk` z aktywnym SS na ramkę).
- Źródeł behawioralnych ALU nie ma w repozytorium, jest tylko netlista. Tabele operacji w [exe_unit_alu.md](exe_unit_alu.md) odtworzono, symulując **wszystkie 16 × 256 × 256 kombinacji** wejść netlisty i dopasowując funkcje. Każda opisana funkcja i flaga zgadza się z netlistą w 100% przypadków. Nazwy funkcji to interpretacja, a zachowanie jest pewne.
