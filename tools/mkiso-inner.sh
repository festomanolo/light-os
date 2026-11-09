#!/bin/sh
#
# Light OS (festomanolo): pack an ISO tree into a hybrid ISO that boots on
# BIOS and UEFI, from optical media and from a USB stick written raw (dd,
# Ndaga Fijo direct mode, Rufus DD mode, ...).
#
# Runs on Linux (natively or inside the builder container) and needs:
#   xorriso, mkfs.vfat (dosfstools), mtools, isohdpfx.bin (isolinux package)
#
# Usage: sh mkiso-inner.sh <iso tree> <output.iso> <volume label>
################################################################################
set -e

ROOT="$1"; OUT="$2"; LABEL="${3:-PORTEUS}"
[ -d "$ROOT/EFI/boot" ] && [ -f "$ROOT/boot/syslinux/isolinux.bin" ] || {
    echo "mkiso-inner: $ROOT is not a Light OS ISO tree" >&2; exit 1; }

MBR=""
for f in /usr/lib/ISOLINUX/isohdpfx.bin /usr/lib/syslinux/bios/isohdpfx.bin \
         /usr/share/syslinux/isohdpfx.bin; do
    [ -r "$f" ] && { MBR="$f"; break; }
done
[ -n "$MBR" ] || { echo "mkiso-inner: isohdpfx.bin not found" >&2; exit 1; }

# 1. UEFI boot image: a FAT filesystem holding Syslinux EFI plus the files its
#    menu loads. EFI/boot/syslinux.cfg includes ../../boot/syslinux/porteus.cfg,
#    which loads /boot/syslinux/{vmlinuz,initrd.xz,porteus.png}.
EFIIMG="$ROOT/boot/efiboot.img"
rm -f "$EFIIMG"
kib=$(du -sk "$ROOT/EFI" "$ROOT/boot/syslinux/vmlinuz" "$ROOT/boot/syslinux/initrd.xz" \
       "$ROOT/boot/syslinux/porteus.cfg" "$ROOT/boot/syslinux/porteus.png" | awk '{s+=$1} END{print s}')
kib=$(( kib + 2048 ))                       # FAT overhead and slack
dd if=/dev/zero of="$EFIIMG" bs=1024 count="$kib" status=none
mkfs.vfat -n EFIBOOT "$EFIIMG" >/dev/null
export MTOOLS_SKIP_CHECK=1
mmd -i "$EFIIMG" ::/EFI ::/EFI/boot ::/boot ::/boot/syslinux
mcopy -i "$EFIIMG" "$ROOT"/EFI/boot/* ::/EFI/boot/
for f in vmlinuz initrd.xz porteus.cfg porteus.png; do
    mcopy -i "$EFIIMG" "$ROOT/boot/syslinux/$f" ::/boot/syslinux/
done

# 2. Hybrid ISO: El Torito BIOS (isolinux) + El Torito UEFI (efiboot.img),
#    MBR boot code for BIOS USB boot and a GPT/MBR entry for the EFI image
#    so UEFI firmware finds it when the ISO is written to a USB stick.
xorriso -as mkisofs \
    -o "$OUT" \
    -l -J -joliet-long -R -D \
    -A "$LABEL" -V "$LABEL" \
    -isohybrid-mbr "$MBR" \
    -b boot/syslinux/isolinux.bin -c boot/syslinux/isolinux.boot \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/efiboot.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$ROOT"
