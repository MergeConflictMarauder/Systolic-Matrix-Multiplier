# Generic Synopsys Design Compiler starting point for Lab 3 Part III.
# Run from part_3/ with a course-supplied technology library, for example:
#   export TARGET_LIB=/path/to/standard_cells.db
#   export DESIGN_TOP=matmul_8x8_systolic   # or matmul_4x4_systolic
#   export CLOCK_NS=10
#   dc_shell -f synth/run_dc.tcl
# NOTE: Actual synthesis requires a standard-cell .db library, provided
# by the course/EDA environment. This file is a template, NOT a report.

if {![info exists ::env(TARGET_LIB)]} {
    error "Missing TARGET_LIB. Set this to the path to your course .db library."
}
set top matmul_8x8_systolic
if {[info exists ::env(DESIGN_TOP)]} {set top $::env(DESIGN_TOP)}
if {$top ne "matmul_8x8_systolic" && $top ne "matmul_4x4_systolic"} {
    error "DESIGN_TOP must be matmul_4x4_systolic or matmul_8x8_systolic"
}
set period 10.0
if {[info exists ::env(CLOCK_NS)]} {set period $::env(CLOCK_NS)}
set_app_var target_library [list $::env(TARGET_LIB)]
set_app_var link_library [concat "*" $target_library]

set rtl [list ../matmul_pkg.sv ../part_1/FP8_AddSub.sv                ../part_1/FP8_Mult.sv ../matmul.sv]
if {$top eq "matmul_8x8_systolic"} {lappend rtl matmul_8x8.sv}
analyze -format sverilog $rtl
elaborate $top
current_design $top
link
check_design
create_clock -name core_clk -period $period [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks core_clk]
# I/O constraints are provisional: use your instructor's constraints if given.
set_input_delay 0.2 -clock core_clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.2 -clock core_clk [all_outputs]
compile_ultra

file mkdir synth/reports
redirect -file synth/reports/${top}_area.txt { report_area -hierarchy }
redirect -file synth/reports/${top}_timing.txt { report_timing -delay_type max -max_paths 10 }
redirect -file synth/reports/${top}_qor.txt { report_qor }
puts "Completed synthesis of $top with period ${period} ns."
puts "Reports are in synth/reports; verify paths/constraints before quoting Fmax."
