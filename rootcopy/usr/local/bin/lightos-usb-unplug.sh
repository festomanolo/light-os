#!/bin/sh
#
# Light OS (festomanolo): called by udev when a block device is removed.
# If the removed device is the Light OS boot stick, reset the machine at once
# so the PC comes back up in its normal OS. RAM is lost on reset, so nothing
# of the live session is left behind.
#
# Only shell builtins are used after the decision: the boot stick may hold the
# very binaries (sync, reboot, ...) that we would otherwise try to execute.
#
# Args: $1 = filesystem label (may be empty)   $2 = kernel name (sdb1, sdb ...)
# Opt out with the "nounplug" cheatcode. Tests: LIGHTOS_DRYRUN=1, LIGHTOS_RUN=dir
################################################################################

label="${1:-}"
kname="${2:-}"
run="${LIGHTOS_RUN:-/run}"

read -r cmdline < /proc/cmdline 2>/dev/null
case " $cmdline " in *" nounplug "*) exit 0 ;; esac

# whole-disk name of the removed node: sdb1 -> sdb, nvme0n1p1 -> nvme0n1
disk="$kname"
case "$kname" in
    nvme*p[0-9]*|mmcblk*p[0-9]*) disk="${kname%p[0-9]*}" ;;
    sd[a-z]*[0-9]|vd[a-z]*[0-9]|hd[a-z]*[0-9]) disk="${kname%%[0-9]*}" ;;
esac

# If the boot watcher recorded the boot disk(s), only those count.
# Without a record (watcher not running) fall back to the label match.
if [ -r "$run/lightos-bootdisk" ]; then
    hit=0
    while read -r d; do
        [ "$d" = "$disk" ] && hit=1
    done < "$run/lightos-bootdisk"
    [ "$hit" = 1 ] || exit 0
else
    case "$label" in
        PORTEUS|PORTEUX|EFIBOOT|porteus|porteux|usrdata) ;;
        *) exit 0 ;;
    esac
fi

if [ -n "${LIGHTOS_DRYRUN:-}" ]; then echo "REBOOT disk=$disk"; exit 0; fi

echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
