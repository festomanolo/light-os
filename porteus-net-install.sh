#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
# Support for expert users wishing to test on-demand installation starts from
#
# URL: https://raw.githubusercontent.com/festonolo/light-os
# VER:                         /refs/tags/v0.3.6/porteus-net-install.sh
# MAN:                           ?tab=readme-ov-file#usage-quick--dirty
#
# It is suggest testing on a spare machine that does NOT hold valuable data,
# possibly using a Porteus MATE v5.1 with the network support available.
#
################################################################################
set +o noclobber
set +u
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")

store_dirn="moonwalker"
usage_strn="[<type> <url> <arch> <vers>] [/dev/sdx] [it]"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

export porteus_type=${porteus_type:-MATE}
export porteus_arch=${porteus_arch:-x86_64}
export porteus_version=${porteus_version:-Porteus-v5.1} #current

## RAF: defined by `mirror-selection` script
export sha256_file=${sha256_file:-sha256sums.txt}
export mirror_file=${mirror_file:-porteus-mirror-selected.txt}
export mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org/porteus}

# RAF: internal values #________________________________________________________

modules_script_name="porteus-xzm-download.sh"
mirrors_script_name="porteus-mirror-selection.sh"
usbinst_script_name="porteus-usb-install.sh"

# RAF: basic common functions #_________________________________________________

function asking_help() { grep -qe "help" -e "\-h" /proc/$$/cmdline; }
function is_on_demand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { echo; echo -e "$@"; } >&2; } # RAF, TODO: to align printf
function errexit() { echo; exit ${1:-1}; }
function tabout() { sed -e 's,^.,    &,'; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function search() {
    local d ldirs=". $wdr $workingd_path .." f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
}

# RAF: basic common check & set #_______________________________________________

if is_on_demand; then
    wdr=$PWD
    perr "###############################################"
    perr "This is an on-demand from remote running script"
    perr "###############################################"
else
    test -n "$wdr" && wdr=$(realpath $wdr)
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

if isdevel; then
    perr "download path: $download_path\nworkingd path: $workingd_path"
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

# RAF: internal check & set and early functions #_______________________________

user="festonolo"
proj="light-os"
repo="https://github.com/$user/$proj"
rawu="https://raw.githubusercontent.com/$user/$proj"

tagver="v0.3.6"
reftyp="tags"

