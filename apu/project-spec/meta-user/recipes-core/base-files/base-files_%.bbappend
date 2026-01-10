dirs755 += "/run/media/mmcblk0p1"
  
do_install:append() {
    sed -i '/mmcblk0p1/ {
        s/^#//g
        s|/media/card|/run/media/mmcblk0p1|g
    }' ${D}${sysconfdir}/fstab
    
    # Add nofail if not already present for qemu
    sed -i '/mmcblk0p1/s/\(defaults[^[:space:]]*\)/\1,nofail/' ${D}${sysconfdir}/fstab
}