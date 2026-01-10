# Pi-Radio Realtime Petalinux Project
This project is based on Xilinx ZCU111 BSP for Petalinux 2023.2, with additional rftool related updates ported from the rfdc BSP for Petalinux 2021.2. 

## Dependencies
* [Petalinux 2023.2](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools.html)

# Rebuilding the Project
## Updating the XSA
If the .xsa file is updated, copy the new .xsa file from 
```bash
<root>/pl/project/zcu111_rfsoc_trd_wrapper.xsa
``` 
to 
```bash
<root>/apu
```
The `build.sh` script will automatically pick it up from the apu/ directory. If no XSA is found, the project will be built using the existing system.xsa under `project-spec/hw-description/`.

## Build Steps
1. Source the Petalinux 2023.2 env
```bash
source <petalinux-install-path>/settings.sh
```
2. Run the build script
``` bash
chmod +x build.sh
./build.sh
```
Optional env variables can be used to enable .wic and .bsp outputs
```bash
# Generate a .wic image at the end
WIC=1 ./build.sh

# Generate .bsp file at the end
BSP=1 ./build.sh

# to generate both
WIC=1 BSP=1 ./build.sh
```
Once the .wic file is generated (can be found under `apu/images/linux/`), flash the sdcard using tools like Balena Etcher or Win32 Disk Imager. 

The .wic image creates two partitions on the SD card: /boot and /root. All boot files including `autostart.sh` and `network.conf` files can be found in /boot partition.

Before booting the FPGA, update the `network.conf` file as required for your setup.
## Updating only FPGA binary
If only the FPGA image has changed (in case of no PS interface changes), a full petalinux build is not required.

1. Run the following command to generate a .bif file. Ensure .bit file is available in the same dir.
```
echo 'all:
{
	[destination_device = pl] zcu111_rfsoc_trd_wrapper.bit
}' > convert.bif
```
2. Generate the .bit file in .bit.bin format
```
petalinux-package --force --boot --bif convert.bif -o mts.bit.bin
```
3. Copy the file to `/lib/firmware/xilinx/mts/`
4. Reboot the system or restart the rftool app after removing the overlay.
```bash
reboot

# or

fpgautil -R
rftool &
```
