VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = demo_tb

# Usage: make run    compile and simulate, save the output to simulation.log
#        make waves  compile with waveform dumping, simulate, open Verdi

SIM       = simv
SIM_WAVES = simv_waves
TB        = tb/demo_tb.v
FSDB      = demo.fsdb
LOG       = simulation.log

# The testbench includes ../header_tb/matmul_8x8_test_utils.vh
INCDIR    = +incdir+../header_tb

# ../rtl/matmul_with_ram.sv is shared with parts 2 and 3; MATMUL_8X8 selects the
# 8x8 version, which also provides the ram module used by part 4's top level
DEFINES   = +define+MATMUL_8X8

# RTL source files (the package must be compiled first, and apb_slave.sv
# before matmul_with_apb.sv because it defines the register macros).
# Part 1's FP8 units are tested directly; part 4's APB top level brings
# part 3's 8x8 array, which is built from the 4x4 arrays of part 2.
RTL       = ../rtl/matmul_pkg.sv \
            ../rtl/fp8/FP8_AddSub.sv \
            ../rtl/fp8/FP8_Mult.sv \
            ../rtl/matmul.sv \
            ../part_3_8x8/rtl/matmul_8x8.sv \
            ../rtl/matmul_with_ram.sv \
            ../part_4_apb/rtl/apb_slave.sv \
            ../part_4_apb/rtl/matmul_with_apb.sv

.PHONY: all compile run waves clean

# Default: compile the design and testbench
all: compile

# Compile the design and testbench
compile:
	$(VCS) $(VCS_FLAGS) $(INCDIR) $(DEFINES) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run the demo and save terminal output
run: compile
	./$(SIM) -exitstatus 2>&1 | tee $(LOG)

# Run the demo with FSDB dumping and open the waveform in Verdi
waves:
	$(VCS) $(VCS_FLAGS) $(INCDIR) $(DEFINES) +define+FSDB_DUMP -top $(TOP) $(RTL) $(TB) -o $(SIM_WAVES)
	./$(SIM_WAVES) -exitstatus 2>&1 | tee $(LOG)
	verdi -dbdir $(SIM_WAVES).daidir -ssf $(FSDB) -sswr signal.rc &

# Remove generated simulation and waveform files
clean:
	rm -rf $(SIM) $(SIM).daidir $(SIM_WAVES) $(SIM_WAVES).daidir \
	       csrc ucli.key DVEfiles novas_dump.log verdiLog \
	       $(FSDB) $(LOG) *.vpd
