# Pi-Radio - Real time beamformer

This project is built on top of Pi-Radio 8ch-if design and adds a real-time beamforming pipeline in the FPGA fabric.

## Repo Structure
The repo contains 
- PL side vivado project
- Petalinux project 
- Host side drivers to communicate with the RFSoC.

```
├── apu
│   ├── autostart.sh
│   ├── build.sh
│   ├── network.conf
│   ├── project-spec
│   └── README.md
├── host
│   ├── config
│   ├── demos
│   ├── helper
│   ├── +piradio
│   └── README.md
├── LICENSE
├── pl
│   ├── constrs
│   ├── Makefile
│   ├── project
│   ├── README.md
│   ├── scripts
│   └── srcs
└── README.md
```

# FPGA Project (pl)
The `pl/` directory contains the two vivado projects for the real-time beamformer.

1. Hardware Implementation Project
    - Based on the Pi-Radio non-real time 8ch-if design
    - Extended to include the real time processing core
    - Used to generate the FPGA bitstream and export the hardware (.xsa) for Petalinux
2. Standalone Simulation Project
    - Used to simulate the `rt_core` independently with AXI-VIP instead of ZynqMP

Refer to pl/README.md for detailed build, simulation, and export instructions.

# Petalinux Project (apu)
The `apu/` dir contains the petalinux project used to build the runtime software and SD card images for RFSoC. Refer to `apu/README.md` for:
- Build instructions
- FPGA binary update workflow
- Setup and boot instructions

# Host Drivers (host)
The `host/` directory contains the host-side drivers used to control and communicate with the RFSoC. This is a direct copy of the non real-time drivers from the 8ch-if project, with extensions to the FullyDigital class. Refer to `host/README.md` for more detailed changes and usage. 