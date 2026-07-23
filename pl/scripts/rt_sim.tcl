# Create and run the standalone real-time processing simulation.
#
# This script is intended to be run from pl/ through `make sim`, but all input
# paths are resolved relative to the script so it is independent of the
# caller's working directory.

set script_dir  [file dirname [file normalize [info script]]]
set pl_dir      [file normalize "$script_dir/.."]
set project_dir "$pl_dir/rt_sim"
set rtl_dir     "$pl_dir/srcs/rtl"
set ip_dir      "$pl_dir/srcs/ip/ip_repo"
set tb_dir      "$pl_dir/srcs/tb"
set hex_dir     "$tb_dir/hex"

set project_name "rt_sim"
set design_name  "design_1"
set part_name    "xczu28dr-ffvg1517-2-e"
set board_part   "xilinx.com:zcu111:part0:1.4"

create_project $project_name $project_dir -part $part_name -force
set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    "$rtl_dir/axis_skidbuffer.sv" \
    "$rtl_dir/axis_mux.v" \
    "$rtl_dir/axis_combine.v" \
    "$rtl_dir/axis_demux.v" \
    "$rtl_dir/axil_io.sv" \
    "$rtl_dir/axis_broadcast.sv" \
    "$rtl_dir/rt_proc_core.svh" \
    "$rtl_dir/rt_proc_core.sv" \
    "$rtl_dir/core_unit.sv" \
    "$rtl_dir/axis_reg.v" \
    "$rtl_dir/rt_summation.sv" \
    "$rtl_dir/xcmult.sv" \
    "$rtl_dir/rt_proc_core_v.v" \
    "$rtl_dir/rt_proc_ctrl.sv" \
]

set ip_files [list \
    "$ip_dir/fracDelayFIR/fracdelay.coe" \
    "$ip_dir/fracDelayFIR/fracDelayFIR.xci" \
    "$ip_dir/GainCrrtFir/GainCorr.coe" \
    "$ip_dir/GainCrrtFir/GainCrrtFir.xci" \
]

foreach required_file [concat $rtl_files $ip_files [list "$tb_dir/wrapper_tb.sv"]] {
    if {![file isfile $required_file]} {
        error "Required simulation source is missing: $required_file"
    }
}

add_files -norecurse -fileset sources_1 $rtl_files
add_files -norecurse -fileset sources_1 $ip_files
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
update_compile_order -fileset sources_1

source "$script_dir/rt_sim_bd.tcl"
validate_bd_design
save_bd_design

set bd_file [get_files -quiet "${design_name}.bd"]
if {[llength $bd_file] != 1} {
    error "Expected one ${design_name}.bd after sourcing rt_sim_bd.tcl"
}

generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse -fileset sources_1 $wrapper_files
set_property top "${design_name}_wrapper" [get_filesets sources_1]
update_compile_order -fileset sources_1

add_files -norecurse -fileset sim_1 "$tb_dir/wrapper_tb.sv"
set_property include_dirs [list $rtl_dir] [get_filesets sim_1]
set_property top wrapper_tb [get_filesets sim_1]

set required_hex_files {}
foreach test_index {0 1 2 3 4} {
    set suffix [format "%02d" $test_index]
    foreach prefix {input output phases memory_init} {
        lappend required_hex_files "${prefix}_${suffix}.hex"
    }
}

foreach hex_name $required_hex_files {
    set hex_file "$hex_dir/$hex_name"
    if {![file isfile $hex_file]} {
        error "Required simulation vector is missing: $hex_file"
    }
}

set hex_files [glob -nocomplain -directory $hex_dir *.hex]
add_files -norecurse -fileset sim_1 $hex_files
update_compile_order -fileset sim_1

launch_simulation
run all
