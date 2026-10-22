VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = matmul_apb_tb

# Usage: make <compile|run|waves> <ones|random|exception>
TESTS     = ones random exception
ACTIONS   = all compile run waves run_all clean

# The test is chosen by naming it on the command line (default: exception)
TEST      = $(or $(filter $(TESTS),$(MAKECMDGOALS)),exception)

UNKNOWN   = $(filter-out $(TESTS) $(ACTIONS),$(MAKECMDGOALS))
ifneq ($(UNKNOWN),)
$(error Unknown target or test '$(UNKNOWN)'. Tests: $(TESTS))
endif

ifneq ($(words $(TEST)),1)
$(error Choose one test: make <target> ones, random or exception)
endif

# Seed for the random test
SEED      = 1

SIM       = simv
SIM_WAVES = simv_waves
TB        = matmul_apb_tb.v
FSDB      = $(TEST)_apb.fsdb
LOG       = $(TEST)_simulation.log

# The testbench includes the shared reference model ../fp8_ref_model.vh
INCDIR    = +incdir+..

# ../matmul_with_ram.sv is shared with parts 2 and 3; MATMUL_8X8 selects the
# 8x8 version, which also provides the ram module used here
DEFINES   = +define+MATMUL_8X8

# RTL source files (the package must be compiled first, and apb_slave.sv
# before matmul_with_apb.sv because it defines the register macros)
RTL       = ../matmul_pkg.sv \
            ../part_1/FP8_AddSub.sv \
            ../part_1/FP8_Mult.sv \
            ../matmul.sv \
            ../part_3/matmul_8x8.sv \
            ../matmul_with_ram.sv \
            apb_slave.sv \
            matmul_with_apb.sv

.PHONY: $(ACTIONS) $(TESTS)

# Default: compile the design and testbench
all: compile

# Compile the design and testbench (one build serves every test)
compile:
	$(VCS) $(VCS_FLAGS) $(INCDIR) $(DEFINES) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run the selected test and save terminal output
run: compile
	./$(SIM) -exitstatus +TEST=$(TEST) +SEED=$(SEED) 2>&1 | tee $(LOG)

# Run the selected test with FSDB dumping and open the waveform in Verdi
waves:
	$(VCS) $(VCS_FLAGS) $(INCDIR) $(DEFINES) +define+FSDB_DUMP -top $(TOP) $(RTL) $(TB) -o $(SIM_WAVES)
	./$(SIM_WAVES) -exitstatus +TEST=$(TEST) +SEED=$(SEED) 2>&1 | tee $(LOG)
	verdi -dbdir $(SIM_WAVES).daidir -ssf $(FSDB) &

# Run every test and print a PASS/FAIL summary (fails if any test fails)
run_all: compile
	@status=0; \
	for t in $(TESTS); do \
	  ./$(SIM) -exitstatus +TEST=$$t +SEED=$(SEED) > $${t}_simulation.log 2>&1; \
	  if grep -q '^PASS' $${t}_simulation.log; then echo "PASS  $$t"; \
	  else echo "FAIL  $$t  (see $${t}_simulation.log)"; status=1; fi; \
	done; \
	exit $$status

# `ones`, `random` and `exception` only select the test. Given alone, they compile.
$(TESTS): $(if $(filter $(ACTIONS),$(MAKECMDGOALS)),,compile)
	@:

# Remove generated simulation and waveform files
clean:
	rm -rf $(SIM) $(SIM).daidir $(SIM_WAVES) $(SIM_WAVES).daidir \
	       csrc ucli.key DVEfiles novas_dump.log verdiLog \
	       *_apb.fsdb *_simulation.log *.vpd
