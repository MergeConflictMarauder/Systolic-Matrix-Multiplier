# Part 3
SHELL     := /bin/bash
VCS       ?= vcs
VERDI     ?= verdi
VCS_FLAGS ?= -sverilog -full64 -kdb -debug_access+all
TOP       := tb_matmul_8x8
CASE      ?= ones
CASES     := ones identity overflow

RTL       := ../matmul_pkg.sv \
             ../part_1/FP8_AddSub.sv \
             ../part_1/FP8_Mult.sv \
             ../matmul.sv \
             matmul_8x8.sv \
             matmul_with_ram.sv
TB        := tb_matmul_8x8.sv

.PHONY: all compile run run_all waves clean help
all: compile

help:
	@echo 'make compile                  Compile into simv_8x8'
	@echo 'make run CASE=ones            Run 8x8 all-ones scenario'
	@echo 'make run CASE=identity        Run 8x8 identity scenario'
	@echo 'make run CASE=overflow        Run 8x8 exception scenario'
	@echo 'make run_all                  Run all three cases'
	@echo 'make waves CASE=identity      Generate FSDB, launch Verdi'
	@echo 'make clean                    Remove all generated artifacts'

compile:
	$(VCS) $(VCS_FLAGS) -top $(TOP) $(RTL) $(TB) -o simv_8x8

run: compile
	@case " $(CASES) " in *" $(CASE) "*) ;; *) echo "Unsupported CASE=$(CASE)"; exit 1 ;; esac
	@set -o pipefail; ./simv_8x8 -exitstatus +TEST=$(CASE) 2>&1 | tee $(CASE)_simulation.log

run_all: compile
	@set -e; for t in $(CASES); do \
	  echo "========== $$t =========="; \
	  ./simv_8x8 -exitstatus +TEST=$$t > $${t}_simulation.log 2>&1 || { cat $${t}_simulation.log; exit 1; }; \
	  cat $${t}_simulation.log; \
	done

waves:
	@case " $(CASES) " in *" $(CASE) "*) ;; *) echo "Unsupported CASE=$(CASE)"; exit 1 ;; esac
	$(VCS) $(VCS_FLAGS) +define+FSDB_DUMP -top $(TOP) $(RTL) $(TB) -o simv_8x8_waves
	@set -o pipefail; ./simv_8x8_waves -exitstatus +TEST=$(CASE) 2>&1 | tee $(CASE)_simulation.log
	$(VERDI) -dbdir simv_8x8_waves.daidir -ssf $(CASE)_fp8.fsdb &

clean:
	rm -rf simv_8x8 simv_8x8.daidir simv_8x8_waves simv_8x8_waves.daidir \
	       csrc ucli.key DVEfiles novas_dump.log verdiLog VerdiLog *.fsdb *.vpd *.log
