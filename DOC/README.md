# Dokumentacja projektu SPI

Projekt to magistrala SPI z jednym masterem i trzema slave'ami. Każdy slave to zdalnie wywoływana jednostka arytmetyczno-logiczna (ALU). Master wysyła w jednej 28-bitowej ramce dwa 8-bitowe argumenty i 4-bitowy kod operacji. Slave liczy wynik i odsyła go (8 bitów wyniku + 4 flagi) w **następnej** ramce.

## Spis treści

| Dokument | Zawartość |
|---|---|
| [protokol_spi.md](protokol_spi.md) | **Jak działa interfejs**: sygnały, format ramki, przebiegi czasowe zbocze po zboczu, potok (opóźnienie jednej ramki), przykład transakcji |
| [spi_master.md](spi_master.md) | `MODEL/SPI_MASTER/spi_master.sv`: porty, parametry, FSM, ścieżki danych |
| [spi_exe_unit.md](spi_exe_unit.md) | `MODEL/SPI_EXE_UNIT_N/spi_exe_unit_N.sv`: slave, FSM odbioru, rejestry, różnice między jednostkami |
| [exe_unit_alu.md](exe_unit_alu.md) | `MODEL/SPI_EXE_UNIT_N/exe_unit*_rtl.sv`: pełna tabela operacji i flag trzech ALU (odtworzona z netlist) |
| [bloki_pomocnicze.md](bloki_pomocnicze.md) | `shifter.sv` i `watchdog.sv`: rejestr przesuwny i licznik |
| [synteza_i_symulacja.md](synteza_i_symulacja.md) | `WORK/makefile`, skrypty Yosysa `*.ys`, `TEST/testbench.sv`, wektory `*.vh`, `testbench_do_pliku_txt.sv` |

Lista znanych błędów i proponowanych poprawek jest w [głównym README](../README.md#lista-napraw-i-ulepszeń). Ta dokumentacja opisuje **stan obecny**, razem z jego dziwactwami.

## Architektura

```
                         TESTBENCH (TEST/testbench.sv)
 ┌────────────────────────────────────────────────────────────────────────┐
 │                                                                        │
 │  send_data[27:0] ─┐                                                    │
 │  send_request ────┤  ┌──────────────┐   o_mosi ──────┬──────┬──────┐   │
 │  clk, rst ────────┼─►│  spi_master  │   o_sclk ──────┼──┬───┼──┬───┼─┐ │
 │                   │  │              │   o_ss   ──────┼──┼─┬─┼──┼─┬─┼─┼┐│
 │  received_data ◄──┼──│ o_data       │                ▼  ▼ ▼ ▼  ▼ ▼ ▼ ▼▼│
 │  master_busy ◄────┘  │ o_busy       │             ┌──────┐┌──────┐┌──────┐
 │                      │       i_miso │◄──┐         │slave1││slave2││slave3│
 │                      └──────────────┘   │         │ ALU1 ││ ALU2 ││ ALU3 │
 │                                         │         └──┬───┘└──┬───┘└──┬───┘
 │                                         │   s_miso[0]│ [1]   │  [2]  │
 │                                         │         ┌──▼───────▼───────▼──┐
 │                                         └─────────│ MUX (select_slave)  │
 │                                                   └─────────────────────┘
 └────────────────────────────────────────────────────────────────────────┘
```

- **Master** (`spi_master`) dostaje z zewnątrz 28-bitowe słowo i impuls `i_send`. Generuje SCLK (połowa częstotliwości `i_clk`) i SS, wysyła słowo przez MOSI i jednocześnie odbiera 28 bitów z MISO.
- **Slave'y** (`spi_exe_unit_1/2/3`) są taktowane wyłącznie przez SCLK. Wszystkie trzy mają podłączone to samo SS, więc **każdy odbiera każdą ramkę** i każdy liczy swój wynik.
- **Wybór slave'a** robi wyłącznie testbench: multiplekser wybiera, którego MISO słucha master (`select_slave`). Sam master nie ma pojęcia o wielu slave'ach.

## Katalog plików

| Plik | Rola | Dokumentacja |
|---|---|---|
| `README.md` | Opis projektu i lista napraw | — |
| `.gitignore` | Ignoruje wygenerowane netlisty `RTL/spi*`, logi, `waves.vcd`, `signals.gtkw`, pliki `*.run` i `DOC/*.json` | — |
| `DOC/` | Ta dokumentacja. Tu Yosys zapisuje też `spi_exe_unit_1.json` (plik generowany, ignorowany) | — |
| `MODEL/SPI_MASTER/spi_master.sv` | Master SPI | [spi_master.md](spi_master.md) |
| `MODEL/SPI_MASTER/shifter.sv` | Rejestr przesuwny | [bloki_pomocnicze.md](bloki_pomocnicze.md#shifter) |
| `MODEL/SPI_MASTER/watchdog.sv` | Licznik okresu | [bloki_pomocnicze.md](bloki_pomocnicze.md#watchdog) |
| `MODEL/SPI_EXE_UNIT_1/spi_exe_unit_1.sv` | Slave 1 (wrapper SPI wokół ALU 1) | [spi_exe_unit.md](spi_exe_unit.md) |
| `MODEL/SPI_EXE_UNIT_1/exe_unit_1_rtl.sv` | Netlista ALU 1 (moduł `exe_unit_rtl`) | [exe_unit_alu.md](exe_unit_alu.md#jednostka-1) |
| `MODEL/SPI_EXE_UNIT_2/spi_exe_unit_2.sv` | Slave 2 | [spi_exe_unit.md](spi_exe_unit.md) |
| `MODEL/SPI_EXE_UNIT_2/exe_unit_rtl_2.sv` | Netlista ALU 2 (moduł `exe_unit_rtl_2`) | [exe_unit_alu.md](exe_unit_alu.md#jednostka-2) |
| `MODEL/SPI_EXE_UNIT_3/spi_exe_unit_3.sv` | Slave 3 | [spi_exe_unit.md](spi_exe_unit.md) |
| `MODEL/SPI_EXE_UNIT_3/exe_unit_rtl.sv` | Netlista ALU 3 (moduł `exe_unit_rtl`, ta sama nazwa co ALU 1!) | [exe_unit_alu.md](exe_unit_alu.md#jednostka-3) |
| `MODEL/SPI_EXE_UNIT_N/shifter.sv`, `watchdog.sv` | Identyczne kopie plików z `SPI_MASTER/` | [bloki_pomocnicze.md](bloki_pomocnicze.md) |
| `RTL/.gitkeep` | Pusty katalog na netlisty generowane przez `make rtl` | [synteza_i_symulacja.md](synteza_i_symulacja.md) |
| `WORK/makefile` | Cele `rtl`, `sim`, `clear`, `wave` | [synteza_i_symulacja.md](synteza_i_symulacja.md#makefile) |
| `WORK/spi_master.ys`, `spi_slave_{1,2,3}.ys` | Skrypty syntezy Yosysa | [synteza_i_symulacja.md](synteza_i_symulacja.md#skrypty-yosysa-ys) |
| `TEST/testbench.sv` | Testbench całego systemu (na netlistach) | [synteza_i_symulacja.md](synteza_i_symulacja.md#testbench) |
| `TEST/test_spi_exe_unit_{1,2,3}.vh` | Wektory testowe dołączane przez `` `include `` | [synteza_i_symulacja.md](synteza_i_symulacja.md#wektory-testowe-vh) |
| `TEST/testbench_do_pliku_txt.sv` | Stary generator wektorów dla ALU (niekompilowalny) | [synteza_i_symulacja.md](synteza_i_symulacja.md#testbench_do_pliku_txtsv) |

## Szybki start

```bash
cd WORK
make rtl     # Yosys: MODEL/* -> RTL/*_rtl.sv (netlisty AND/OR/XOR + przerzutniki)
make sim     # Icarus: RTL/*.sv + TEST/testbench.sv, wynik: liczba błędnych/poprawnych transferów
make wave    # GTKWave: WORK/waves.vcd
```

Zweryfikowany wynik (Yosys 0.69, Icarus Verilog 12.0): **2610 poprawnych, 1 błędny transfer**. Błąd pochodzi z pierwszego wektora `test_spi_exe_unit_3.vh`, szczegóły w [synteza_i_symulacja.md](synteza_i_symulacja.md#znany-błąd-wektora).

## Skąd pochodzą informacje

- Porty, FSM i protokół opisano na podstawie kodu źródłowego. Przebiegi czasowe są potwierdzone symulacją (29 zboczy SCLK i 59 cykli `i_clk` z aktywnym SS na ramkę).
- Źródła behawioralne ALU nie są w repozytorium, są tylko netlisty. Tabele operacji w [exe_unit_alu.md](exe_unit_alu.md) odtworzono, symulując **wszystkie 16 × 256 × 256 kombinacji** wejść każdej netlisty i dopasowując funkcje. Każda opisana funkcja i flaga zgadza się z netlistą w 100% przypadków. Nazwy funkcji to interpretacja, a zachowanie jest pewne.
