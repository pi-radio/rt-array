# Pi-Radio FPGA Projects
This directory constains the FPGA Vivado projects for the Pi-Radio real-time beamformer. 

## Dependencies
* [Vivado 2023.2](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools.html)

## Hardware Implementation Project
This project is based on the existing Pi-Radio non-realtime design, with extensions to include the real-time processing core. 

### Build
To create the project, run synthesis, implementation, generate the bitstream and export the hardware
```bash
cd pl
make vivado
# or
vivado -mode batch -source scripts/create_project.tcl -nolog -nojournal
```
The project is generated under `pl/project/` and the exported hardware .xsa can be found at `pl/project/zcu111_rfsoc_trd_wrapper.xsa`. Copy the `.xsa` to `apu/` before building the petalinux project.

### Updating the Project Files
To regenerate the block design script after any change, run the following command and commit the updated script to git. 

```bash
write_bd_tcl scripts/zcu111_rfsoc_trd_bd.tcl -force
```

The `create_project.tcl` script uses can `zcu111_rfsoc_trd_bd.tcl` script to recreate the complete Vivado project. 

If you make any project setting changes that must persist, add the required tcl commands to `create_project.tcl`. 

If you add new source files, constraint files, or IP files to the project, also update the file list at `create_project.tcl:31` so the project can be recreated correctly on another machine.
```tcl
set files [list \
 [file normalize "$srcs_dir/rtl/axis_skidbuffer.sv"] \
 [file normalize "$srcs_dir/rtl/axis_mux.v"] \
 [file normalize "$srcs_dir/rtl/axis_combine.v"] \
 [file normalize "$srcs_dir/rtl/axis_demux.v"] \
 [file normalize "$srcs_dir/rtl/axil_io.sv"] \
 [file normalize "$srcs_dir/rtl/axis_broadcast.sv"] \
 [file normalize "$srcs_dir/rtl/rt_proc_core.svh"] \
 [file normalize "$srcs_dir/rtl/rt_proc_core.sv"] \
 [file normalize "$srcs_dir/rtl/core_unit.sv"] \
 [file normalize "$srcs_dir/rtl/axis_reg.v"] \
 [file normalize "$srcs_dir/rtl/rt_summation.sv"] \
 [file normalize "$srcs_dir/rtl/xcmult.sv"] \
 [file normalize "$srcs_dir/rtl/rt_proc_core_v.v"] \
 [file normalize "$srcs_dir/rtl/rt_proc_ctrl.sv"] \
 [file normalize "$srcs_dir/ip/ip_repo/fracDelayFIR/fracDelayFIR.xci"]\
 [file normalize "$srcs_dir/ip/ip_repo/GainCrrtFir/GainCrrtFir.xci"]\
]
```

### Maintaining XCI Files
If you add a new Xilinx IP to the design, add its `.xci` file to `pl/srcs/ip/ip_repo/<ip_name>/<ip_name>.xci` and include it in the file list in the `create_project.tcl` script. 

For clean IP file generation, you can set the following fields in the `.xci` file to `.gen`:

```json
"gen_directory": ".gen"
```

Set `OUTPUTDIR` in `runtime_parameters` to `.gen`:

```json
"OUTPUTDIR": [ { "value": ".gen" } ]
```

Use `pl/srcs/ip/ip_repo/fracDelayFIR/fracDelayFIR.xci` as a reference.

## Standalone Simulation Project

### Simulation
To create the simulation project and run the testbench, run the following from the `pl/` directory.
```bash
make sim
```
This command first runs a python script to generate the required stimulus files, and then runs the vivado script to build and run the simulation.

To regenerate the bd script after any change, run the following command and commit the updated script. 
```tcl
write_bd_tcl scripts/rt_sim_bd.tcl -force
```
Follow the instructions above for updating the project files. This project uses `rt_sim.tcl` in place of `create_project.tcl`
