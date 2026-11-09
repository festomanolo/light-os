#!/bin/bash
#
# Light OS: Rebuild a Porteus ISO with all Light OS customizations:
#   - Instant boot (TIMEOUT 5 / 0.5s), default entry runs from USB (no RAM copy wait)
#   - Kernel cmdline parameters from cmdline.txt (+ a "copy to RAM" menu entry)
#   - Light OS boot screen & desktop wallpapers (efiboot/ + rootcopy/)
#   - Auto-reboot udev rule & handler when the USB is unplugged (rootcopy/)
#   - Light OS initrd (initrd/initrd.xz): faster USB detection, internal disks not scanned
#   - Hybrid ISO that boots BIOS and UEFI, from DVD or a raw-written USB stick
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
CDLABEL="PORTEUS"   # kept: the Porteus initrd and the unplug watcher look for it
LIGHTOS_VERSION="1.0"

if [ -z "$INPUT_ISO" ]; then
    # Auto-detect ISO in repo, lightos/, or ~/Downloads
    for cand in \
        "$REPO_DIR"/*.iso \
        "$REPO_DIR"/lightos/*.iso \
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

# 2. Apply efiboot customizations (Light OS boot screen)
echo "[Light OS] Injecting efiboot assets..."
if [ -d "$REPO_DIR/efiboot" ]; then
    cp -af "$REPO_DIR/efiboot"/. "$ISOROOT"/
    rm -f "$ISOROOT/boot/syslinux/black.png" "$ISOROOT/boot/syslinux/bootlogo.png" 2>/dev/null || :
fi

# 2b. Light OS initrd: Light OS boot messages, 0.2s USB polling, 'usbonly' scan
if [ -r "$REPO_DIR/initrd/initrd.xz" ]; then
    echo "[Light OS] Installing Light OS initrd..."
    cp -f "$REPO_DIR/initrd/initrd.xz" "$ISOROOT/boot/syslinux/initrd.xz"
fi

# 3. Apply rootcopy customizations (udev USB unplug auto-reboot, wallpapers, dconf)
echo "[Light OS] Injecting rootcopy customizations (including udev unplug auto-reboot)..."
if [ -d "$REPO_DIR/rootcopy" ]; then
    rm -rf "$ISOROOT/porteus/rootcopy"   # no stale files from an earlier Light OS build
    mkdir -p "$ISOROOT/porteus/rootcopy"
    cp -RLf "$REPO_DIR/rootcopy"/. "$ISOROOT/porteus/rootcopy"/
    if [ -r "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus.gz" ]; then
        gzip -dc "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus.gz" \
            > "$ISOROOT/porteus/rootcopy/home/guest/.config/dconf/porteus"
    fi
    chmod a+rx "$ISOROOT/porteus/rootcopy/usr/local/bin"/* "$ISOROOT/porteus/rootcopy/etc/rc.d/rc.local" 2>/dev/null || :
fi

# 4. Copy any extra .xzm modules in repo root or lightos/
for xzm in "$REPO_DIR"/*.xzm "$REPO_DIR"/lightos/*.xzm; do
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
        -e "s,^APPEND changes=[^/]*/porteus.*$,APPEND changes=/porteus ${KARGS}," \
        -e "s,^APPEND copy2ram.*$,APPEND copy2ram ${KARGS}," \
        -e "s,^MENU LABEL Graphics mode,MENU LABEL Light OS - fast boot (run from USB)," \
        -e "s,^MENU LABEL Copy To RAM,MENU LABEL Light OS - copy to RAM (stick can be removed)," \
        -e "s,^MENU TITLE .*,MENU TITLE Light OS ${LIGHTOS_VERSION} 64bit by festomanolo," \
        -e 's,Porteus Save File Manager,@@PSFM@@,g' \
        -e 's,Porteus,Light OS,g' \
        -e 's,@@PSFM@@,Porteus Save File Manager,g' \
        "$CFG_FILE" > "$CFG_FILE.tmp"
    mv -f "$CFG_FILE.tmp" "$CFG_FILE"
    grep -n -e "TIMEOUT" -e "APPEND changes=" "$CFG_FILE" | sed 's/^/  /'
fi

# 6. Build the hybrid BIOS + UEFI ISO (tools/mkiso-inner.sh), natively on
#    Linux when the tools are installed, otherwise in a cached Docker image
echo "[Light OS] Building bootable ISO (BIOS + UEFI): $OUTPUT_ISO ..."
cp -f "$REPO_DIR/tools/mkiso-inner.sh" "$WORKDIR/mkiso-inner.sh"
if [ "$(uname -s)" = "Linux" ] && command -v xorriso >/dev/null 2>&1 \
   && command -v mkfs.vfat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then
    sh "$WORKDIR/mkiso-inner.sh" "$ISOROOT" "$OUTPUT_ISO" "$CDLABEL"
elif command -v docker >/dev/null 2>&1; then
    OUT_FILE="$(basename "$OUTPUT_ISO")"
    BUILDER_IMG="lightos-isobuilder:2"
    # Cache the toolchain in a local image so later builds skip apt entirely
    if ! docker image inspect "$BUILDER_IMG" >/dev/null 2>&1; then
        echo "[Light OS] Creating builder image $BUILDER_IMG (one time)..."
        printf 'FROM debian:bookworm-slim\nRUN apt-get update -qq && apt-get install -y -qq --no-install-recommends xorriso isolinux dosfstools mtools >/dev/null && rm -rf /var/lib/apt/lists/*\n' \
            | docker build -q -t "$BUILDER_IMG" - >/dev/null
    fi
    docker run --rm -v "$WORKDIR:/work" "$BUILDER_IMG" \
        sh /work/mkiso-inner.sh /work/isoroot "/work/$OUT_FILE" "$CDLABEL"
    mv -f "$WORKDIR/$OUT_FILE" "$OUTPUT_ISO"
else
    echo "ERROR: need Linux with xorriso, dosfstools and mtools, or docker, to pack the ISO." >&2
    exit 1
fi

ls -lh "$OUTPUT_ISO"
echo "[Light OS] Successfully rebuilt ISO: $OUTPUT_ISO"
