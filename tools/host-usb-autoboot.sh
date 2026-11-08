#!/bin/bash
#
# Light OS: Host-side USB insertion watcher & auto-reboot service (macOS & Linux)
# Watches for the Light OS USB volume (PORTEUS / PORTEUX / EFIBOOT) and
# automatically reboots the machine into Light OS when plugged in.
#
# Usage:
#   sudo bash tools/host-usb-autoboot.sh --install     # Install background service
#   sudo bash tools/host-usb-autoboot.sh --uninstall   # Remove background service
#   bash tools/host-usb-autoboot.sh --watch [--dry-run]# Watch in foreground
#
################################################################################
set -e

LABELS=("PORTEUS" "PORTEUX" "EFIBOOT")
BIN_PATH="/usr/local/bin/lightos-host-autoboot"
PLIST_PATH="/Library/LaunchDaemons/org.lightos.usb-autoboot.plist"
UDEV_RULE_PATH="/etc/udev/rules.d/99-lightos-host-autoboot.rules"
DRY_RUN=0

for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=1
    fi
done

usage() {
    cat <<EOF
Usage: $(basename "$0") [--install | --uninstall | --watch | --trigger] [--dry-run]

Options:
  --install     Install persistent auto-reboot watcher service (LaunchDaemon on macOS, udev rule on Linux)
  --uninstall   Remove persistent auto-reboot watcher service
  --watch       Watch in foreground for Light OS USB insertion (${LABELS[*]})
  --trigger     Internal callback executed when USB is detected
  --dry-run     Detect USB and print boot action without rebooting
EOF
}

find_mounted_lightos_macos() {
    local lbl
    for lbl in "${LABELS[@]}"; do
        if [ -d "/Volumes/$lbl" ]; then
            echo "/Volumes/$lbl"
            return 0
        fi
    done
    return 1
}

find_attached_lightos_linux() {
    local lbl
    for lbl in "${LABELS[@]}"; do
        if [ -e "/dev/disk/by-label/$lbl" ]; then
            echo "/dev/disk/by-label/$lbl"
            return 0
        fi
    done
    return 1
}

reboot_into_lightos() {
    local target="$1"
    local os_name
    os_name="$(uname -s)"

    echo "[Light OS] Detected Light OS boot media: $target"

    if [ "$DRY_RUN" = "1" ]; then
        echo "[Light OS] --dry-run enabled: skipping bless/efibootmgr and system reboot."
        return 0
    fi

    if [ "$os_name" = "Darwin" ]; then
        # Attempt to set next boot to the EFI USB volume on Intel Macs
        if [ -d "$target" ]; then
            bless --mount "$target" --setBoot --nextonly 2>/dev/null || \
            bless --mount "$target" --setBoot 2>/dev/null || :
        fi
        sync
        /sbin/shutdown -r now "Light OS USB inserted - rebooting into Light OS"
    elif [ "$os_name" = "Linux" ]; then
        # Avoid triggering if we are already running inside Porteus/Light OS live environment
        if [ -d "/mnt/live" ] || grep -q "porteus" /proc/cmdline 2>/dev/null; then
            echo "[Light OS] Already running inside Light OS; ignoring insertion."
            return 0
        fi
        # If efibootmgr is installed, prefer setting USB as BootNext
        if command -v efibootmgr >/dev/null 2>&1; then
            usb_bootnum=$(efibootmgr | sed -ne 's/^Boot\([0-9A-Fa-f]\{4\}\)\*.*\(USB\|Removable\|UEFI:\).*/\1/p' | head -n1)
            if [ -n "$usb_bootnum" ]; then
                efibootmgr -n "$usb_bootnum" >/dev/null 2>&1 || :
            fi
        fi
        sync
        systemctl reboot 2>/dev/null || /sbin/reboot 2>/dev/null || reboot
    fi
}

do_trigger() {
    local os_name target=""
    os_name="$(uname -s)"
    if [ "$os_name" = "Darwin" ]; then
        target="$(find_mounted_lightos_macos || :)"
    else
        target="$(find_attached_lightos_linux || :)"
    fi
    if [ -n "$target" ]; then
        reboot_into_lightos "$target"
    fi
}

do_watch() {
    local os_name target=""
    os_name="$(uname -s)"
    echo "[Light OS] Watching for Light OS USB (${LABELS[*]}) on $os_name... (Press Ctrl+C to stop)"
    while true; do
        if [ "$os_name" = "Darwin" ]; then
            target="$(find_mounted_lightos_macos || :)"
        else
            target="$(find_attached_lightos_linux || :)"
        fi
        if [ -n "$target" ]; then
            reboot_into_lightos "$target"
            break
        fi
        sleep 1
    done
}

do_install() {
    if [ "$(id -u)" != "0" ]; then
        echo "ERROR: --install requires root privileges (use sudo)." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$BIN_PATH")"
    cp -f "$0" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    local os_name
    os_name="$(uname -s)"
    if [ "$os_name" = "Darwin" ]; then
        cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.lightos.usb-autoboot</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
        <string>--trigger</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/Volumes</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
        chmod 644 "$PLIST_PATH"
        launchctl unload "$PLIST_PATH" 2>/dev/null || :
        launchctl load -w "$PLIST_PATH"
        echo "[Light OS] Installed macOS LaunchDaemon at $PLIST_PATH"
    elif [ "$os_name" = "Linux" ]; then
        cat > "$UDEV_RULE_PATH" <<EOF
# Light OS Host Auto-Reboot: Reboot into Light OS when USB is inserted
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_LABEL}=="PORTEUS|PORTEUX|EFIBOOT", RUN+="$BIN_PATH --trigger"
EOF
        chmod 644 "$UDEV_RULE_PATH"
        udevadm control --reload-rules 2>/dev/null || :
        echo "[Light OS] Installed Linux udev rule at $UDEV_RULE_PATH"
    else
        echo "ERROR: Unsupported OS '$os_name'" >&2
        exit 1
    fi
}

do_uninstall() {
    if [ "$(id -u)" != "0" ]; then
        echo "ERROR: --uninstall requires root privileges (use sudo)." >&2
        exit 1
    fi
    if [ -f "$PLIST_PATH" ]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || :
        rm -f "$PLIST_PATH"
        echo "[Light OS] Removed $PLIST_PATH"
    fi
    if [ -f "$UDEV_RULE_PATH" ]; then
        rm -f "$UDEV_RULE_PATH"
        udevadm control --reload-rules 2>/dev/null || :
        echo "[Light OS] Removed $UDEV_RULE_PATH"
    fi
    rm -f "$BIN_PATH"
    echo "[Light OS] Uninstalled host USB auto-boot watcher."
}

case "${1:-}" in
    --install)   do_install ;;
    --uninstall) do_uninstall ;;
    --watch)     do_watch ;;
    --trigger)   do_trigger ;;
    -h|--help|"") usage ;;
    *)           usage; exit 1 ;;
esac
