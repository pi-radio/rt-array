# Pi-Radio Non-Realtime FPGA Project

## Dependencies
* [Vivado 2023.2](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools.html)

## Building the project
The following command will create the project, run synthesis, implementation, generate the bitstream and export the hardware (`.xsa`) in `project/zcu111_rfsoc_trd.xsa`. We will use the `.xsa` file to configure the Petalinux project.
```console
$ vivado -mode batch -source scripts/create_project.tcl -nolog -nojournal
```