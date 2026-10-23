# /**************************************************/
# /* Design Compiler synthesis script               */
# /* 8x8 FP8 systolic matrix multiplier (part 3)    */
# /*                                                */
# /* Synthesizes only matmul_8x8_systolic: the four */
# /* 4x4 arrays and the 8x8 sequencing logic, not   */
# /* the RAMs or the start/done control FSM.        */
# /*                                                */
# /* Run from part_3_8x8/:                          */
# /*   make synth                                   */
# /* or from part_3_8x8/synth/:                     */
# /*   dc_shell-t -f run_dc.tcl                     */
# /*                                                */
# /* OSU FreePDK 45nm (needs PDK_DIR set)           */
# /**************************************************/


# User/project-specific settings

# RTL source files, relative to part_3_8x8/synth/.
# matmul_pkg.sv must come first because the other files
# import its package.
set my_verilog_files [list \
    ../../rtl/matmul_pkg.sv \
    ../../rtl/fp8/FP8_AddSub.sv \
    ../../rtl/fp8/FP8_Mult.sv \
    ../../rtl/matmul.sv \
    ../rtl/matmul_8x8.sv \
]

# RTL top-level module
set my_toplevel matmul_8x8_systolic

# Clock port name (the design has a single clock)
set my_clock_pin clk

# Starting target frequency.
# This is a synthesis target, not necessarily the final Fmax.
# Start here and adjust upward when checking timing.
# Can be overridden from the environment: CLK_MHZ=500 make synth
set my_clk_freq_MHz 1000
if {[info exists ::env(CLK_MHZ)]} {
    set my_clk_freq_MHz $::env(CLK_MHZ)
}

# Optional external input/output delay assumptions
set my_input_delay_ns  0.1
set my_output_delay_ns 0.1


#/**************************************************/
#/* No modifications needed below                  */
#/**************************************************/

# OSU FreePDK 45nm library
set OSU_FREEPDK [format "%s%s" \
    [getenv "PDK_DIR"] \
    "/osu_soc/lib/files"]

set search_path [concat $search_path $OSU_FREEPDK]
set alib_library_analysis_path $OSU_FREEPDK

set link_library [concat \
    [list gscl45nm.db] \
    [list dw_foundation.sldb]]

set target_library "gscl45nm.db"

define_design_lib WORK -path ./WORK

set verilogout_show_unconnected_pins true

set_ultra_optimization true
set_ultra_optimization -force


# Read RTL

analyze -format sverilog $my_verilog_files

elaborate $my_toplevel

current_design $my_toplevel

link
uniquify


# Clock definition

set my_period [expr 1000.0 / $my_clk_freq_MHz]

create_clock \
    -name CLK \
    -period $my_period \
    [get_ports $my_clock_pin]


# Driving cell
set_driving_cell -lib_cell INVX1 [all_inputs]


# Input/output timing assumptions

# Every port except the clock belongs to the single CLK domain.
# reset and pe_reset are synchronous resets (sampled on posedge clk),
# so unlike an asynchronous reset they are timed like any other input.
set my_inputs  [remove_from_collection [all_inputs] [get_ports $my_clock_pin]]
set my_outputs [all_outputs]

set_input_delay \
    $my_input_delay_ns \
    -clock CLK \
    $my_inputs

set_output_delay \
    $my_output_delay_ns \
    -clock CLK \
    $my_outputs


# Synthesis

compile -ungroup_all -map_effort medium

compile -incremental_mapping -map_effort medium


# Checks

check_design

check_timing

report_constraint -all_violators


# Create report directory
file mkdir reports


# Timing reports
redirect reports/timing.rep {
    report_timing \
        -delay_type max \
        -max_paths 10
}

# Clock information
redirect reports/clocks.rep {
    report_clocks
}

# Constraint information
redirect reports/constraints.rep {
    report_constraint -all_violators
}

# Timing sanity check
redirect reports/check_timing.rep {
    check_timing
}


# Area

redirect reports/area.rep {
    report_area
}

redirect reports/area_hierarchy.rep {
    report_area -hierarchy
}


# Power
redirect reports/power.rep {
    report_power
}


# Save synthesized design
set filename [format "%s%s" $my_toplevel ".ddc"]
write -format ddc -hierarchy -output $filename

set filename [format "%s%s" $my_toplevel ".sdc"]
write_sdc $filename



# Finish
quit
