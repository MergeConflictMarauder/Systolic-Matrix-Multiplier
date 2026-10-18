# Systolic-Matrix-Multiplier

A 4x4 systolic-array matrix multiplier built on FP8 (E3M4) arithmetic.

| Folder | Contents |
|---|---|
| `part_1/` | FP8 adder/subtractor and multiplier, with their testbench |
| `part_2/` | Systolic matrix multiplier using the FP8 units, with two testbenches |
| `part_3/` | TBD |
| `part_4/` | TBD |

## Requirements

Synopsys **VCS** (to compile and simulate) and **Verdi** (to view waveforms) must be on your `PATH`.

## Part 1: FP8 adder and multiplier

```bash
cd part_1
make run      # compile, simulate, save the output to simulation.log
make waves    # compile, simulate, open the waveform in Verdi
make clean    # delete generated files
```

`make` alone only compiles. The testbench runs 5 test cases for each unit and prints `PASS` or `FAIL`.

## Part 2: Matrix multiplier

Add the test name, `normal` or `exception`, after the command:

```bash
cd part_2
make run normal         # compile and simulate the normal test
make run exception      # compile and simulate the exception test
make waves normal       # simulate and open the waveform in Verdi
make waves exception
make run_all            # run both tests
make clean              # delete generated files for both tests
```

| Test | What it checks |
|---|---|
| `normal` | A 4x4 multiply with no FP8 exceptions. Expects `exception_flags = 00000`. |
| `exception` | A multiply that includes 8.0 x 8.0, which overflows FP8. Expects an exception flag to be raised and C[0][0] = +infinity (`0x70`). |

If no test is named, `normal` is used. Naming both at once is an error.

## Part 3: TBD

_TBD_

```bash
cd part_3
# TBD
```

## Part 4: TBD

_TBD_

```bash
cd part_4
# TBD
```

### Output files

| Command | Terminal output saved to | Waveform |
|---|---|---|
| `make run` / `make waves` (part 1) | `simulation.log` | `FP8_tb.fsdb` |
| `make run normal` (part 2) | `normal_simulation.log` | `normal_fp8.fsdb` |
| `make run exception` (part 2) | `exception_simulation.log` | `exception_fp8.fsdb` |
| `tbd` (part 3) | `tbd` | `tbd` |
| `tbd` (part 3) | `tbd` | `tbd` |