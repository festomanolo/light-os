#!/bin/sh
#
# Light OS: Triggered by udev when a USB block device is unplugged.
# If the Light OS boot USB is no longer attached, cleanly unmount stale
# mountpoints and immediately reboot the machine back into its normal OS.
#
################################################################################

LABEL="${1:-}"
DEVNAME="${2:-}"
LOCKDIR="/tmp/lightos-usb-unplug.lock"

boot_usb_present() {
    for lbl in PORTEUS PORTEUX EFIBOOT porteus porteux usrdata; do
        if [ -e "/dev/disk/by-label/$lbl" ]; then
            return 0
        fi
    done
    if command -v blkid >/dev/null 2>&1; then
        if blkid | grep -Eq 'LABEL="(PORTEUS|PORTEUX|EFIBOOT|porteus|porteux|usrdata)"'; then
            return 0
        fi
    fi
    return 1
}

case "$LABEL" in
    PORTEUS|PORTEUX|EFIBOOT|porteus|porteux|usrdata)
        TRIGGER=1
        ;;
    *)
        # Give udev 300ms to finish removing /dev/disk/by-label symlinks
        sleep 0.3 2>/dev/null || sleep 1
        if boot_usb_present; then
            exit 0
        fi
        TRIGGER=1
        ;;
esac

if [ "${TRIGGER:-0}" = "1" ]; then
    mkdir "$LOCKDIR" 2>/dev/null || exit 0

    # Flush pending writes (bounded so removed media cannot hang sync)
    sync &
    sleep 0.5 2>/dev/null || sleep 1

    # Lazy-unmount any USB partitions to prevent shutdown hang
    umount -l /mnt/live/memory/changes 2>/dev/null || :
    umount -l /mnt/sd* 2>/dev/null || :

    # Reboot immediately back into the normal internal OS
    /sbin/reboot -f 2>/dev/null || reboot -f 2>/dev/null || :
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || :
    echo b > /proc/sysrq-trigger 2>/dev/null || :
fi
