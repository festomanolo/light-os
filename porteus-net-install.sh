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

################################################################################
if asking_help; then usage errexit 0; elif false; then errexit
#///////////////////////////////////////////////////////////////////////////////

echo '#!/bin/bash
stat=$(head -c35 /proc/$PPID/stat)
pcmd=$(echo $(strings /proc/$PPID/cmdline))
echo 0:$0:$$ ppid:$PPID pcmd:$pcmd stat:$stat
' | tee test.sh | grep -v .; chmod a+x test.sh

cmd=$(echo $(strings /proc/$$/cmdline))
echo me cmd:$$:$cmd; bash -i <(cat test.sh)

# RAF: output from the code above to make properly work the code below
# me cmd:2170724:bash /dev/fd/63
# 0:/dev/fd/62:2170760 ppid:2170724 pcmd:bash /dev/fd/63
#                      stat:2170724 (bash) S 1786462 2170724 17

tagver="v0.3." # To replace with the lastest available in tags
rawurl="https://raw.githubusercontent.com/festonolo"
rawurl="$rawurl/light-os/refs/tags/$tagver"
rawurl="$rawurl/porteus-net-install.sh"
DEVEL=0 # bash -i <(wget -qO- $net_inst_url)

#\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
elif [ "x$1" == "x--clean" ]; then #############################################
    if amiroot; then
        if [ ! -n "${SUDO_USER}" ]; then
            perr "ERROR: try as user, variable \$SUDO_USER is void/unset, abort!"
            errexit
        fi
        perr "WARNING: please execute this script as user, not as root"
        chown -R ${SUDO_USER}.${SUDO_USER} $d
        errexit
    fi
    d=$download_path
    if [ ! -d "$d" ]; then
        perr "ERROR: folder '$d' does not exit, abort!"
        errexit
    fi
    if [ "$(realpath $PWD)" == "$(realpath $d)" ]; then
        perr "WARNING: deleting current directory, prompt 'cd .' or 'cd ..' afterwards"
    fi
    set +x
    while true; do
        # RAF: better use mktemp here
        rd="$d.$RANDOM"
        if [ ! -d $rd ]; then mkdir $rd && break; fi
        sleep 0.1
    done
    # RAF: this piece of code should be isolated, it can delete itself.
    (
        isolist=$(command ls -1t $d/*.{ISO,iso,xzm} 2>/dev/null ||:)       
        if [ -n "$isolist" ]; then
            mv -f $isolist $rd && rm -rf $d && mv $rd $d
            perr "INFO: the ISO and .xzm files are left untouched, do it manually"
        else
            rm -rf $d && mv $rd $d
            perr "done."
        fi
        errexit 0
    )
elif [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then # RAF: isn't a kind of magic!?
    usage echo
elif amiroot; then
    perr "This script is NOT supposed being executed by root, abort!"
    errexit
elif [ "$download_path" == "$workingd_path" ]; then # Avoid to over-write myself
    d="$download_path/tmp"; mkdir -p "$d"; cp -f "$0" "$d/$shs"
    exec bash "$d/$shs" "$@"   # exec replaces this process, no return from here
    perr "ERROR: exec fails or a bug hits here, abort!"; errexit -1 # eventually
else ###########################################################################
