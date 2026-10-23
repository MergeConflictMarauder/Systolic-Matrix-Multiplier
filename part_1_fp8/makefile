VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = FP8_tb
SIM       = simv
FSDB      = $(TOP).fsdb

# RTL source files
RTL       = ../rtl/fp8/FP8_AddSub.sv \
            ../rtl/fp8/FP8_Mult.sv

TB        = tb/FP8_tb.v

# The testbench includes the shared reference model ../header_tb/fp8_ref_model.vh
INCDIR    = +incdir+../header_tb

.PHONY: all compile run waves clean

# Default: compile the waveform simulation
all: compile

# Compile the design and testbench
compile:
	$(VCS) $(VCS_FLAGS) $(INCDIR) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run the simulation and save terminal output
run: compile
	./$(SIM) -exitstatus 2>&1 | tee simulation.log

# Run the simulation and open the waveform in Verdi
waves: compile
	./$(SIM) -exitstatus 2>&1 | tee simulation.log
	verdi -dbdir $(SIM).daidir -ssf $(FSDB) &

# Remove generated simulation and waveform files
clean:
	rm -rf $(SIM) $(SIM).daidir csrc ucli.key DVEfiles \
	       novas_dump.log $(FSDB) simulation.log \
	       *.vpd