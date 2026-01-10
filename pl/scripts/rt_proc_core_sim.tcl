# =====================================================================
# Vivado TCL Script: Create or Open Project, Add Sources, Build BD,
# Create Wrapper, and Run Simulation
# Usage:
# vivado -mode gui -source rt_proc_core_sim.tcl
# =====================================================================

# Get directory of this script
set script_dir [file dirname [file normalize [info script]]]

# Project configuration
set project_name "rt_proc_core_sim"
set project_dir  "$script_dir/$project_name"
set part_name    "xczu7ev-ffvc1156-2-e"

# ============================================================
# Create or open project
# ============================================================
if {[file exists $project_dir]} {
    puts "Opening existing project: $project_dir"
    open_project $project_dir/$project_name.xpr

    # puts "Launching simulation..."
    # launch_simulation
    # run all
} else {
    puts "Creating new project: $project_dir"
    create_project $project_name $project_dir -part $part_name
}

# ============================================================
# Add Sources (relative paths)
# ============================================================
set rtl_dir "$script_dir/../srcs/rtl"
set tb_dir  "$script_dir/../srcs/tb"
set ip_dir "$script_dir/../srcs/ip/ip_repo"
set hex_dir "$script_dir/../../host/helper/hex"

# Add RTL
if {[file exists $rtl_dir]} {
    add_files -fileset sources_1 [glob -directory $rtl_dir *.v *.sv *.svh]
}

# Add IP Cores and generate thm
add_files -fileset sources_1 $ip_dir/fracDelayFIR/fracDelayFIR.xci
add_files -fileset sources_1 $ip_dir/GainCrrtFir/GainCrrtFir.xci

generate_target all [get_files $ip_dir/fracDelayFIR/fracDelayFIR.xci]
generate_target all [get_files $ip_dir/GainCrrtFir/GainCrrtFir.xci]

# Add testbench files
if {[file exists $tb_dir]} {
    add_files -fileset sim_1 [glob -directory $tb_dir *.sv *.v]
}

# Add stimulus hex files
set stim_files {
    memory_init_tx.hex
    memory_init_rx.hex
    input_tx.hex
    output_tx.hex
    input_rx.hex
    output_rx.hex
}

foreach f $stim_files {
    add_files -fileset sim_1 $hex_dir/$f
}

update_compile_order -fileset sources_1

set_property top wrapper_tb [get_fileset sim_1]
update_compile_order -fileset sim_1

# ============================================================
# Source Block Design TCL
# ============================================================
set bd_script "$script_dir/rt_proc_core_sim_bd.tcl"
set bd_files [get_files *.bd]

if {[llength $bd_files] > 0} {
    puts "Block Design already exists. Skipping BD creation."
} else {
    if {[llength $bd_script] > 0} {
        puts "Sourcing Block Design script: $bd_script"
        source $bd_script

        set bd_files [get_files *.bd]
        if {[llength $bd_files] > 0} {
            set bd_file [lindex $bd_files 0]
            set bd_name [file rootname [file tail $bd_file]]

            generate_target all [get_files $bd_file]
            
            puts "Creating HDL wrapper for $bd_name"
            make_wrapper -files [get_files $bd_file] -top
            add_files [glob $project_dir/$project_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.vhd \
                            $project_dir/$project_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v]

            set_property top ${bd_name}_wrapper [current_fileset]
        }
    } else {
        error "Block Design TCL script not found. Cannot proceed with BD creation."
    }
}
# ============================================================
# Run Simulation
# ============================================================

puts "Launching simulation..."
launch_simulation
run all
