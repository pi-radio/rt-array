# Pi-Radio FPGA Projects
This directory constains the FPGA Vivado projects for the Pi-Radio real-time beamformer. 

## Dependencies
* [Vivado 2023.2](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools.html)

## Hardware Implementation Project
This project is based on the existing Pi-Radio non-realtime design, with extensions to include the real-time processing core. 

### Build
To create the project, run synthesis, implementation, generate the bitstream and export the hardware
```bash
make vivado
# or
vivado -mode batch -source scripts/create_project.tcl -nolog -nojournal
```
The project is generated under `pl/project/` and the exported hardware .xsa can be found at `pl/project/zcu111_rfsoc_trd_wrapper.xsa`. Copy the `.xsa` to `apu/` before building the petalinux project.

## Standalone Simulation Project

### Simulation
To create the simulation project and run the testbench
```bash
make rt_sim
```