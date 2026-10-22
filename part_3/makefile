VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
DC        = dc_shell-t
TOP       = matmul_tb

# Usage: make <compile|run|waves> <ones|random>
TESTS     = ones random
ACTIONS   = all compile run waves run_all synth clean

# The test is chosen by naming it on the command line (default: ones)
TEST      = $(or $(filter $(TESTS),$(MAKECMDGOALS)),ones)

UNKNOWN   = $(filter-out $(TESTS) $(ACTIONS),$(MAKECMDGOALS))
ifneq ($(UNKNOWN),)
$(error Unknown target or test '$(UNKNOWN)'. Tests: $(TESTS))
endif

ifneq ($(words $(TEST)),1)
$(error Choose one test: make <target> ones  or  make <target> random)
endif

# Seed for the random test
SEED      = 1

SIM       = simv
SIM_WAVES = simv_waves
TB        = matmul_with_ram_tb.v
FSDB      = $(TEST)_fp8.fsdb
LOG       = $(TEST)_simulation.log

# The testbench includes the shared reference model ../fp8_ref_model.vh
INCDIR    = +incdir+..

# ../matmul_with_ram.sv is shared with part 2; MATMUL_8X8 selects its 8x8 top level
DEFINES   = +define+MATMUL_8X8

# RTL source files (the package must be compiled first).
RTL       = ../matmul_pkg.sv \
            ../part_1/FP8_AddSub.sv \
            ../part_1/FP8_Mult.sv \
            ../matmul.sv \
            matmul_8x8.sv \
            ../matmul_with_ram.sv

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

# Synthesize only the 8x8 array with Design Compiler and FreePDK 45nm (needs PDK_DIR).
# Runs inside synth/; reports go to synth/reports/, the netlist to synth/*.ddc.
# Target clock: 1000 MHz by default, override with e.g. CLK_MHZ=500 make synth
synth:
	@test -n "$$PDK_DIR" || { echo "Set PDK_DIR to the FreePDK 45nm install (see synth/run_dc.tcl)"; exit 1; }
	cd synth && $(DC) -f run_dc.tcl 2>&1 | tee synth.log

# `ones` and `random` only select the test. Given alone, they compile.
$(TESTS): $(if $(filter $(ACTIONS),$(MAKECMDGOALS)),,compile)
	@:

# Remove generated simulation, waveform and synthesis scratch files
# (synthesis results in synth/reports/, synth/*.ddc and synth/*.sdc are kept)
clean:
	rm -rf $(SIM) $(SIM).daidir $(SIM_WAVES) $(SIM_WAVES).daidir \
	       csrc ucli.key DVEfiles novas_dump.log verdiLog \
	       *_fp8.fsdb *_simulation.log *.vpd \
	       synth/synth.log synth/command.log synth/filenames.log \
	       synth/default.svf synth/WORK synth/alib-*
