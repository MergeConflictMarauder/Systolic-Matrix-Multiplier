VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = matmul_tb

# Usage: make <compile|run|waves> <normal|exception>
#   e.g. make waves normal, make run exception
TESTS     = normal exception
ACTIONS   = all compile run waves run_all clean

# The test is chosen by naming it on the command line (default: normal)
TEST      = $(or $(filter $(TESTS),$(MAKECMDGOALS)),normal)

ifneq ($(words $(TEST)),1)
$(error Choose one test: make <target> normal  or  make <target> exception)
endif

SIM       = simv_$(TEST)
TB        = tb/$(TEST)_test_tb.v
FSDB      = $(TEST)_fp8.fsdb
LOG       = $(TEST)_simulation.log

# RTL source files (the package must be compiled first)
RTL       = ../rtl/matmul_pkg.sv \
            ../rtl/fp8/FP8_AddSub.sv \
            ../rtl/fp8/FP8_Mult.sv \
            ../rtl/matmul.sv \
            ../rtl/matmul_with_ram.sv

.PHONY: $(ACTIONS) $(TESTS)

# Default: compile the selected test
all: compile

# Compile the design and testbench
compile:
	$(VCS) $(VCS_FLAGS) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run the simulation and save terminal output
run: compile
	./$(SIM) -exitstatus 2>&1 | tee $(LOG)

# Run the simulation and open the waveform in Verdi
waves: compile
	./$(SIM) -exitstatus 2>&1 | tee $(LOG)
	verdi -dbdir $(SIM).daidir -ssf $(FSDB) &

# Run both tests
run_all:
	$(MAKE) run normal
	$(MAKE) run exception

# `normal` and `exception` only select the test. Given alone, they compile it.
$(TESTS): $(if $(filter $(ACTIONS),$(MAKECMDGOALS)),,compile)
	@:

# Remove generated simulation and waveform files for both tests
clean:
	rm -rf simv_normal simv_normal.daidir simv_exception simv_exception.daidir \
	       csrc ucli.key DVEfiles novas_dump.log \
	       normal_fp8.fsdb exception_fp8.fsdb \
	       normal_simulation.log exception_simulation.log \
	       *.vpd
