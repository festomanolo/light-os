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
