#
# This file is the piradio recipe.
#

SUMMARY = "Simple piradio application"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://piradio.c \
		file://pl_if.h \
		file://pl_zynq.c \	
		file://dma.c \	
		file://piradio.h \	
	    file://Makefile \
		  "

S = "${WORKDIR}"

do_compile() {
	     oe_runmake
}

do_install() {
	     install -d ${D}${bindir}
	     install -m 0755 piradio ${D}${bindir}
}
