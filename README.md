# Systolic-Matrix-Multiplier

A systolic-array matrix multiplier built on FP8 (E3M4) arithmetic: a 4x4 array, extended to 8x8 in part 3.

| Folder | Contents |
|---|---|
| `part_1/` | FP8 adder/subtractor and multiplier, with their testbench |
| `part_2/` | 4x4 systolic matrix multiplier using the FP8 units, with two testbenches |
| `part_3/` | 8x8 matrix multiplier built from four 4x4 arrays, with its testbench and synthesis script |
| `part_4/` | TBD |

## Requirements

Synopsys **VCS** (to compile and simulate) and **Verdi** (to view waveforms) must be on your `PATH`.
Part 3 synthesis also needs **Design Compiler** (`dc_shell`) and a standard-cell `.db` library.

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

## Part 3: 8x8 matrix multiplier

Four 4x4 arrays are tiled into an 8x8 array (`matmul_8x8.sv`), with two RAMs per matrix. Its top level, `matrix_multiplication_8x8`, lives in the root `matmul_with_ram.sv`, which is shared with part 2: the makefile compiles it with `+define+MATMUL_8X8`, which selects the 8x8 top level instead of part 2's 4x4 one. Add the test name after the command:

```bash
cd part_3
make run ones           # compile and simulate one test
make run random SEED=7  # random test with a different seed (default 1)
make waves random       # simulate and open the waveform in Verdi
make run_all            # run both tests and print a PASS/FAIL summary
make clean              # delete generated files
```

| Test | What it checks |
|---|---|
| `ones` | A and B all 1.0, so every element of C is 8.0 (`0x60`). |
| `random` | 10 random FP8 matrix pairs, run back to back with no PE reset in between. |

Both tests check all 64 elements of C and the exception flags against a reference model that rounds after every multiply and add, in the same order as the hardware. If no test is named, `ones` is used.

**Synthesis** (8x8 array only, no RAMs or control logic):

```bash
export TARGET_LIB=/path/to/standard_cells.db   # course-supplied library
export CLOCK_NS=10                             # optional, default 10 ns
make synth                                     # reports go to synth/reports/
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
| `make run <test>` / `make waves <test>` (part 3) | `<test>_simulation.log` | `<test>_fp8.fsdb` |
| `make synth` (part 3) | `synth.log` | Reports in `synth/reports/` |