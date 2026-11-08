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
