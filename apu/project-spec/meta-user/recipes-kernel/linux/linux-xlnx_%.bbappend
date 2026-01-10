FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"
SRC_URI += "file://user.cfg"

SRC_URI:append = " \
        file://0001-power-supply-irps-Add-support-for-irps-supply.patch \
        file://0002-drivers-misc-add-support-for-DDR-memory-management.patch \
        file://0003-dmaengine-xilinx_dma-In-SG-cyclic-mode-allow-multipl.patch \
        file://0004-drivers-misc-add-support-for-selecting-mem-type.patch \
        file://0005-i2c-cadence-Implement-timeout.patch \
        file://0006-drivers-misc-change-ADC-packet-size-as-per-FIFO-size.patch \
        file://0007-drivers-misc-change-parameters-for-of_dma_configure.patch \
        file://0008-plmem-clean-up-sysfs-node-and-character-device-nodes.patch \
        file://0009-dma-clean-the-BD-s-only-when-done-bit-is-set.patch \
        file://0010-misc-plmem-replace-dma_declare_memory-with-reserved-.patch \
        file://0011-DMA-changes-as-per-kernel-v5_10.patch \
"
