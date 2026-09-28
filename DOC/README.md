# Dokumentacja projektu SPI

Projekt to magistrala SPI z jednym masterem i jednym slave'em. Slave jest zdalnie wywoływaną jednostką arytmetyczno-logiczną (ALU). Master wysyła w jednej 28-bitowej ramce dwa 8-bitowe argumenty i 4-bitowy kod operacji. Slave liczy wynik i odsyła go (8 bitów wyniku + 4 flagi) w **następnej** ramce.

Pierwotnie w projekcie były trzy slave'y z trzema różnymi ALU napisanymi przez trzech autorów. Zostawiona jest tylko **jednostka 1**. Ślady tamtej architektury opisuje [dziwactwa.md §5](dziwactwa.md#5-ślady-architektury-z-trzema-slaveami).

## Spis treści

| Dokument | Zawartość |
|---|---|
| [protokol_spi.md](protokol_spi.md) | **Jak działa interfejs**: sygnały, format ramki, przebiegi czasowe zbocze po zboczu, potok (opóźnienie jednej ramki), przykład transakcji |
| [spi_master.md](spi_master.md) | `MODEL/SPI_MASTER/spi_master.sv`: porty, parametry, FSM, ścieżki danych |
| [spi_exe_unit.md](spi_exe_unit.md) | `MODEL/SPI_EXE_UNIT_1/spi_exe_unit_1.sv`: slave, FSM odbioru, rejestry |
| [exe_unit_alu.md](exe_unit_alu.md) | `MODEL/SPI_EXE_UNIT_1/exe_unit_1_rtl.sv`: pełna tabela operacji i flag ALU (odtworzona z netlisty) |
| [bloki_pomocnicze.md](bloki_pomocnicze.md) | `shifter.sv` i `watchdog.sv`: rejestr przesuwny i licznik |
| [synteza_i_symulacja.md](synteza_i_symulacja.md) | `WORK/makefile`, skrypty Yosysa `*.ys`, `TEST/testbench.sv`, wektory `*.vh` |
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

## Katalog plików

| Plik | Rola | Dokumentacja |
|---|---|---|
| `README.md` | Opis projektu i lista napraw | — |
| `.gitignore` | Ignoruje wygenerowane netlisty `RTL/spi*`, logi, `waves.vcd`, `signals.gtkw`, pliki `*.run` i `DOC/*.json` | — |
| `DOC/` | Ta dokumentacja. Tu Yosys zapisuje też `spi_exe_unit_1.json` (plik generowany, ignorowany) | — |
| `MODEL/SPI_MASTER/spi_master.sv` | Master SPI | [spi_master.md](spi_master.md) |
| `MODEL/SPI_MASTER/shifter.sv` | Rejestr przesuwny | [bloki_pomocnicze.md](bloki_pomocnicze.md#shifter) |
| `MODEL/SPI_MASTER/watchdog.sv` | Licznik okresu | [bloki_pomocnicze.md](bloki_pomocnicze.md#watchdog) |
| `MODEL/SPI_EXE_UNIT_1/spi_exe_unit_1.sv` | Slave (wrapper SPI wokół ALU) | [spi_exe_unit.md](spi_exe_unit.md) |
| `MODEL/SPI_EXE_UNIT_1/exe_unit_1_rtl.sv` | Netlista ALU (moduł `exe_unit_rtl`) | [exe_unit_alu.md](exe_unit_alu.md) |
| `MODEL/SPI_EXE_UNIT_1/shifter.sv`, `watchdog.sv` | Kopie plików z `SPI_MASTER/` | [bloki_pomocnicze.md](bloki_pomocnicze.md) |
| `RTL/.gitkeep` | Pusty katalog na netlisty generowane przez `make rtl` | [synteza_i_symulacja.md](synteza_i_symulacja.md) |
| `WORK/makefile` | Cele `rtl`, `sim`, `clear`, `wave` | [synteza_i_symulacja.md](synteza_i_symulacja.md#makefile) |
| `WORK/spi_master.ys`, `spi_slave_1.ys` | Skrypty syntezy Yosysa | [synteza_i_symulacja.md](synteza_i_symulacja.md#skrypty-yosysa-ys) |
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
