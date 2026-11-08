#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set +o noclobber
set +u
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")

store_dirn="moonwalker"
usage_strn="[--clean]"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

export sha256_file="sha256sums.txt"
export mirror_file="porteus-mirror-selected.txt"

## RAF: defined by `net-install` script
export porteus_version=${porteus_version:-Porteus-v5.1} #current
export porteus_arch=${porteus_arch:-x86_64}
export porteus_type=${porteus_type:-MATE}

# RAF: internal values #________________________________________________________

wlst=
arch="$porteus_arch"
vers="$porteus_version"
dtst="kernel/64bit.config"
## dtst="bundles/man-lite-porteus-20220607-x86_64-alldesktops.xzm"
## RAF: until the sha256sum.txt files will be restored back, we are tring v5.1

mirror_list="porteus-mirror-allhttps.txt"
netlog_file="porteus-mirror-selected.log"
wgetlogtail="wget-log"

# RAF: basic common functions #_________________________________________________

function askinghelp() { test "x$1" == "x-h" -o "x$1" == "x--help"; } 
function isondemand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { echo; echo -e "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function search() {
    local d ldirs=". $wdr" f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
}

