
if [ "$PETALINUX_VER" = "2023.2" ]; then
    echo "PetaLinux version is 2023.2, continuing..."
else
    echo "Error: PETALINUX_VER is not 2023.2 (found '$PETALINUX_VER')" >&2
    exit 1
fi

if [ -f zcu111_rfsoc_trd_wrapper.xsa ]; then
	echo "Found zcu111_rfsoc_trd_wrapper.xsa, continuing..."
    petalinux-config --silentconfig --get-hw-description=../zcu111_rfsoc_trd_wrapper.xsa
else
	echo "zcu111_rfsoc_trd_wrapper.xsa not found! Copy it to <root>/apu if you want to update the .xsa" >&2
    petalinux-config --silentconfig
fi

petalinux-build

cd images/linux/

petalinux-package --force --boot \
	--fsbl zynqmp_fsbl.elf \
	--pmufw pmufw.elf \
	--u-boot u-boot.elf \
	--fpga system.bit

if [[ "${WIC:-0}" == "1" ]]; then
    echo "Generating WIC image"
    cp ../../autostart.sh .
    cp ../../network.conf .    
    petalinux-package --wic --size 2G,2G --bootfiles "BOOT.BIN image.ub boot.scr autostart.sh network.conf" --wic-extra-args "-c xz"
fi

cd ../../

if [[ "${BSP:-0}" == "1" ]]; then
    echo "Generating BSP"
    petalinux-package --bsp -p . --clean --output piradio_plnx.bsp --force
fi
