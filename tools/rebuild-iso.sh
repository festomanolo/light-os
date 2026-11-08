#!/bin/bash
#
# Light OS: Rebuild a Porteus ISO with all Light OS customizations:
#   - Instant zero-menu boot (TIMEOUT 5 / 0.5s)
#   - Kernel cmdline parameters from cmdline.txt (including copy2ram)
#   - Moonwalker boot screen & desktop wallpapers (efiboot/ + rootcopy/)
#   - Auto-reboot udev rule & handler when the USB is unplugged (rootcopy/)
#   - Hybrid BIOS + UEFI bootable ISO output (label: PORTEUS)
#
# Usage:
#   bash tools/rebuild-iso.sh [/path/to/input.iso] [/path/to/output.iso]
#
################################################################################
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_ISO="${1:-}"
OUTPUT_ISO="${2:-}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-5}"
CDLABEL="PORTEUS"

if [ -z "$INPUT_ISO" ]; then
    # Auto-detect ISO in repo, moonwalker/, or ~/Downloads
    for cand in \
        "$REPO_DIR"/*.iso \
        "$REPO_DIR"/moonwalker/*.iso \
        "$HOME/Downloads"/Porteus-*.iso \
        "$HOME/Downloads"/*porteus*.iso; do
        if [ -f "$cand" ] && [[ "$(basename "$cand")" != LightOS-* ]]; then
            INPUT_ISO="$cand"
            break
        fi
    done
fi

if [ -z "$INPUT_ISO" ] || [ ! -r "$INPUT_ISO" ]; then
    echo "ERROR: Input Porteus ISO not found. Pass path as first argument:" >&2
    echo "  bash tools/rebuild-iso.sh /path/to/Porteus.iso [output.iso]" >&2
    exit 1
fi

INPUT_ISO="$(cd "$(dirname "$INPUT_ISO")" && pwd)/$(basename "$INPUT_ISO")"
if [ -z "$OUTPUT_ISO" ]; then
    BASE_NAME="$(basename "$INPUT_ISO")"
    OUTPUT_ISO="$REPO_DIR/LightOS-${BASE_NAME#LightOS-}"
fi
OUTPUT_ISO="$(cd "$(dirname "$OUTPUT_ISO")" && pwd)/$(basename "$OUTPUT_ISO")"

echo "[Light OS] Input ISO : $INPUT_ISO"
echo "[Light OS] Output ISO: $OUTPUT_ISO"

mkdir -p "$HOME/.cache"
WORKDIR="$HOME/.cache/lightos-iso-rebuild.$$"
ISOROOT="$WORKDIR/isoroot"
mkdir -p "$ISOROOT"

cleanup() {
    if [ -n "${MNT_DIR:-}" ]; then
        if [ "$(uname -s)" = "Darwin" ]; then
            hdiutil detach "$MNT_DIR" >/dev/null 2>&1 || :
        else
            umount "$MNT_DIR" >/dev/null 2>&1 || :
        fi
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# 1. Extract input ISO contents
echo "[Light OS] Extracting base ISO contents..."
if [ "$(uname -s)" = "Darwin" ]; then
    MNT_DIR="$(hdiutil attach -readonly -nobrowse "$INPUT_ISO" | awk -F'\t' 'END{print $3}')"
    cp -a "$MNT_DIR"/. "$ISOROOT"/
    hdiutil detach "$MNT_DIR" >/dev/null
    MNT_DIR=""
else
    if command -v xorriso >/dev/null 2>&1; then
        xorriso -osirrox on -indev "$INPUT_ISO" -extract / "$ISOROOT" >/dev/null 2>&1
    else
        MNT_DIR="$WORKDIR/mnt"
        mkdir -p "$MNT_DIR"
        mount -o loop,ro "$INPUT_ISO" "$MNT_DIR"
        cp -a "$MNT_DIR"/. "$ISOROOT"/
        umount "$MNT_DIR"
        MNT_DIR=""
    fi
fi

chmod -R u+w "$ISOROOT"

# 2. Apply efiboot customizations (Moonwalker boot screen)
echo "[Light OS] Injecting efiboot assets..."
if [ -d "$REPO_DIR/efiboot" ]; then
    cp -af "$REPO_DIR/efiboot"/. "$ISOROOT"/
    rm -f "$ISOROOT/boot/syslinux/black.png" "$ISOROOT/boot/syslinux/bootlogo.png" 2>/dev/null || :
fi

# 3. Apply rootcopy customizations (udev USB unplug auto-reboot, wallpapers, dconf)
echo "[Light OS] Injecting rootcopy customizations (including udev unplug auto-reboot)..."
if [ -d "$REPO_DIR/rootcopy" ]; then
    mkdir -p "$ISOROOT/porteus/rootcopy"
    cp -RLf "$REPO_DIR/rootcopy"/. "$ISOROOT/porteus/rootcopy"/
    if [ -r "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus.gz" ]; then
        gzip -dc "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus.gz" \
            > "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus"
    fi
    chmod a+rx "$ISOROOT/porteus/rootcopy/usr/local/bin"/*.sh 2>/dev/null || :
fi

# 4. Copy any extra .xzm modules in repo root or moonwalker/
for xzm in "$REPO_DIR"/*.xzm "$REPO_DIR"/moonwalker/*.xzm; do
    if [ -f "$xzm" ]; then
        echo "[Light OS] Bundling extra module: $(basename "$xzm")"
        cp -f "$xzm" "$ISOROOT/porteus/modules/"
    fi
done

# 5. Update syslinux/porteus.cfg with TIMEOUT 5 and cmdline.txt (copy2ram, etc.)
CFG_FILE="$ISOROOT/boot/syslinux/porteus.cfg"
KARGS=""
if [ -r "$REPO_DIR/cmdline.txt" ]; then
    KARGS="$(tr '\n' ' ' < "$REPO_DIR/cmdline.txt" | sed 's/[[:space:]]*$//')"
fi

if [ -f "$CFG_FILE" ]; then
    echo "[Light OS] Updating bootloader config (TIMEOUT $BOOT_TIMEOUT, kernel args: $KARGS)..."
    sed -e "s,^\([[:space:]]*[Tt][Ii][Mm][Ee][Oo][Uu][Tt][[:space:]]\{1\,\}\)[0-9]\{1\,\},\1${BOOT_TIMEOUT}," \
        -e "s,APPEND changes=[^/]*/porteus$,& ${KARGS}," \
        "$CFG_FILE" > "$CFG_FILE.tmp"
