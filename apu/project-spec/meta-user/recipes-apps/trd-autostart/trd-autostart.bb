SUMMARY = "TRD Init scripts"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
	file://trd-autostart \
	file://trd-autostart.service \
	"

S = "${WORKDIR}"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
  
inherit update-rc.d systemd

INITSCRIPT_NAME = "trd-autostart"
INITSCRIPT_PARAMS = "start 99 S ."
  
SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "trd-autostart.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
  
do_install() {
	if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
			install -d ${D}${sysconfdir}/init.d/
			install -m 0755 ${WORKDIR}/trd-autostart ${D}${sysconfdir}/init.d/
	fi

	install -d ${D}${bindir}
	install -m 0755 ${WORKDIR}/trd-autostart ${D}${bindir}/
	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${WORKDIR}/trd-autostart.service ${D}${systemd_system_unitdir}
}

FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES','sysvinit','${sysconfdir}/*', '', d)}"
RDEPENDS_${PN}:append = "bash"
