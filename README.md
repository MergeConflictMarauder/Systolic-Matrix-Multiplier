# Systolic-Matrix-Multiplier

A systolic-array matrix multiplier built on FP8 (E3M4) arithmetic: a 4x4 array, extended to 8x8 in part 3.

| Folder | Contents |
|---|---|
| `rtl/` | Design shared by the parts: the package (`matmul_pkg.sv`), the 4x4 systolic array (`matmul.sv`), the top levels with RAMs (`matmul_with_ram.sv`), and the FP8 adder/subtractor and multiplier (`fp8/`) |
| `header_tb/` | Testbench include files: the FP8 reference model and the 8x8 RAM load/check tasks |
| `part_1_fp8/` | Testbench for the FP8 adder/subtractor and multiplier |
| `part_2_4x4/` | Two testbenches for the 4x4 systolic matrix multiplier |
| `part_3_8x8/` | 8x8 matrix multiplier built from four 4x4 arrays (`rtl/`), its testbench (`tb/`) and synthesis script and reports (`synth/`) |
| `part_4_apb/` | The 8x8 multiplier with an APB slave interface in place of the start/done control (`rtl/`), with its testbench (`tb/`) |
| `examples/` | Example testbenches provided with the course |

Each part has its own `makefile`; run the commands below from inside that part's folder.

## Requirements

Synopsys **VCS** (to compile and simulate) and **Verdi** (to view waveforms) must be on your `PATH`.
Part 3 synthesis also needs **Design Compiler** (`dc_shell-t`) and the OSU FreePDK 45nm library (`PDK_DIR` set).

## Part 1: FP8 adder and multiplier

```bash
cd part_1_fp8
make run      # compile, simulate, save the output to simulation.log
make waves    # compile, simulate, open the waveform in Verdi
make clean    # delete generated files
```

`make` alone only compiles. The testbench runs 5 test cases for each unit and prints `PASS` or `FAIL`.

## Part 2: Matrix multiplier

Add the test name, `normal` or `exception`, after the command:

```bash
cd part_2_4x4
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

Four 4x4 arrays are tiled into an 8x8 array (`part_3_8x8/rtl/matmul_8x8.sv`), with two RAMs per matrix. Its top level, `matrix_multiplication_8x8`, lives in `rtl/matmul_with_ram.sv`, which is shared with part 2: the makefile compiles it with `+define+MATMUL_8X8`, which selects the 8x8 top level instead of part 2's 4x4 one. Add the test name after the command:

```bash
cd part_3_8x8
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
export PDK_DIR=/path/to/FreePDK45   # usually set by the course environment
make synth                          # 1000 MHz target; reports go to synth/reports/
CLK_MHZ=500 make synth              # try a different target clock
```

## Part 4: APB slave interface

The part 3 top level's start/done control FSM and its control and status ports are replaced by an APB slave (`part_4_apb/rtl/apb_slave.sv`, completed from the provided skeleton). The new top level, `matrix_multiplication_8x8_apb` in `part_4_apb/rtl/matmul_with_apb.sv`, has the APB signals `PCLK, PRESETn, PADDR, PWRITE, PSEL, PENABLE, PWDATA, PRDATA, PREADY` plus the same RAM ports as part 3. It reuses the part 3 array (`part_3_8x8/rtl/matmul_8x8.sv`) and the `ram` module from `rtl/matmul_with_ram.sv` without changing them.

Every register is 16 bits wide and `PADDR` is the register index. `PREADY` is always 1.

| `PADDR` | Register | Bits | Access | Description |
|---|---|---|---|---|
| 1 | START | [0] | R/W1S | Write 1 to start. Stays 1 while the matmul runs and is cleared by hardware when it is done. Writing 0, or writing 1 while busy, has no effect. |
| 2 | DONE | [15] | R | Set when the operation finishes, cleared when the next one is started. |
| 3 | FLAGS | [4:0] | R | Exception flags {Overflow, Underflow, DivideByZero, Invalid, Inexact}, held after the operation, cleared at the next start. |
| 4 / 5 / 6 | ADDR_A / ADDR_B / ADDR_C | [9:0] | R/W | RAM address of the first column of A, row of B, column of C. Reset value 0. |
| 7 / 8 / 9 | STRIDE_A / STRIDE_B / STRIDE_C | [7:0] | R/W | Address step between columns of A, rows of B, columns of C. Reset value 1. |

Unused bits and unmapped indices read as 0. The testbench drives the bus with the `write` and `read` tasks from `examples/example_tb.v`: it writes the addresses and strides, writes START, polls DONE (`rdata[15]`), then reads FLAGS. Add the test name after the command:

```bash
cd part_4_apb
make run exception      # compile and simulate one test
make waves exception    # simulate and open the waveform in Verdi
make run_all            # run both tests and print a PASS/FAIL summary
make clean              # delete generated files
```

| Test | What it checks |
|---|---|
| `ones` | A and B all 1.0 placed at nonzero addresses with strides 1, 2 and 3, so every element of C is 8.0 (`0x60`) and FLAGS is `00000`. |
| `exception` | A and B all 1.0 except A[0][0] = B[0][0] = 8.0, at the same addresses and strides. 8.0 x 8.0 overflows FP8, so C[0][0] is +infinity (`0x70`), the rest of row 0 and column 0 is 15.0 (`0x6E`), and FLAGS reads `10001` (Overflow, Inexact). |

Each test checks all 64 elements of C against expected values worked out by hand, and the FLAGS value read over APB against the expected flags. If no test is named, `exception` is used.

### Output files

Paths are relative to the part's folder.

| Command | Terminal output saved to | Waveform |
|---|---|---|
| `make run` / `make waves` (part 1) | `simulation.log` | `FP8_tb.fsdb` |
| `make run normal` (part 2) | `normal_simulation.log` | `normal_fp8.fsdb` |
| `make run exception` (part 2) | `exception_simulation.log` | `exception_fp8.fsdb` |
| `make run <test>` / `make waves <test>` (part 3) | `<test>_simulation.log` | `<test>_fp8.fsdb` |
| `make synth` (part 3) | `synth/synth.log` | Reports in `synth/reports/`, netlist in `synth/matmul_8x8_systolic.ddc` |
| `make run <test>` / `make waves <test>` (part 4) | `<test>_simulation.log` | `<test>_apb.fsdb` |