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
usage_strn="[--user-menu] /path/file.iso [/dev/]sdx [it] [--ext4-install]"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

# RAF: internal values #________________________________________________________

## Name of the loop file for having the persistence with a VFAT only system
persistnce_filename="changes.dat"
kernelargs_filename="cmdline.txt"

## Comment this line below to avoid creating the journal in the 2nd partition
journal="yes"

## This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

## Some more options / parameters that might be worth to be customised

guest_owner="1000:100" # guest:users
make_ext4_nojournal="-O ^has_journal"
make_ext4fs_options="-DO fast_commit"
make_ext4fs_lazyone="-E lazy_itable_init=1,lazy_journal_init=1"
make_ext4fs_notlazy="-E lazy_itable_init=0,lazy_journal_init=0"

porteus=${VARIANT:-porteus}
porteus_config_path="/boot/syslinux/${porteus}.cfg"
background_filename="moonwalker-background.jpg"
bootscreen_filename="moonwalker-bootscreen.png"
usbsk_init_filename="porteus-usb-bootable.mbr.gz"

# RAF: basic common functions #_________________________________________________

function is_menu_mode() { grep -q -- "--user-menu" /proc/$$/cmdline; }
function asking_help() { grep -qe "help" -e "\-h" /proc/$$/cmdline; }
function is_on_demand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { printf "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }
function tabout() { sed -e 's,^.,    &,'; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    printf \\n"USAGE: bash ${shs:-$(basename $0)} $usage_strn"\\n
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
    perr \\n"###############################################"
    perr \\n"This is an on-demand from remote running script"
    perr \\n"###############################################"\\n\\n
else
    test -n "$wdr" && wdr=$(realpath $wdr)
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

if isdevel; then
    perr \\n"download path: $download_path\nworkingd path: $workingd_path"\\n
elif amiroot; then
    : # RAF: if the user just did sudo or uid=0, do not drop priviledges caching
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

# RAF: internal check & set and early functions #_______________________________

function is_real_porteus() { test "${porteus}" == "porteus"; }

if is_on_demand; then
    perr \\n"ERROR: this script is NOT supposed being executed on-demand, abort!"
    perr \\n"       For remote installation, use porteus-net-install.sh, instead"\\n
    errexit
fi

################################################################################
if asking_help; then usage errexit 0; else ##################################

function missing() {
    perr \\n"ERROR: file '${1:-}' is missing or wrong type, abort!"\\n
    usage errexit
}

function besure() {
    local ans
    echo
    read -p "${1:-Are you sure to continue}? [N/y] " ans
    ans=${ans^^}; test "${ans:0:1}" == "Y" || return 1
}

function agree() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [Y/n] " ans
    ans=${ans^^}; test "${ans:0:1}" != "N" || return 1
}

function waitdev() {
    local i d=${dev}$1
    for i in $(seq 1 100); do
        sleep 0.1
        partprobe
        if grep -q " $d$" /proc/partitions; then
            test -b /dev/$d
            return $?
        fi; printf .
    done
    perr \\n"ERROR: waitdev('$d') failed, abort!"\\n
    errexit
}

function make4fs() {
    local lbl=$1 dev=$2; shift 2
    { mkfs.ext4 -L "$lbl" ${make_ext4fs_options} -F $dev "$@" || errexit; } \
        2>&1 | grep -v "^mke2fs [0-9.]\+ (" ||:
}

scsi_str=""; scsi_dev="";
function find_last_attached_scsi_unit() {
    local str lst
    str=$(dmesg | grep "] sd .* removable disk" | tail -n1)
    lst=$(echo "$str" | sed -ne "s,.*\[\(sd.\)\].*,\\1,p")
    if [ ! -n "$lst" ]; then
        str=$(dmesg | grep "\[sd[a-z]\] .* removable disk" | tail -n1)
        lst=$(echo "$str" | sed -ne "s,.*\[\(sd.\)\].*,\\1,p")
    fi
    scsi_str="$str"
    scsi_dev="$lst"
}

function check_last_attached_scsi_unit() {
    local dev=$1
    echo
    if [ ! -b /dev/$dev ]; then
        perr "WARNING: error '${dev:+/dev/$dev}' is not a block device, abort!"\\n
        errexit
    fi
    if [ ! -n "$scsi_dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but unable to find the last attached unit."\\n
        besure || errexit
    elif [ "$scsi_dev" != "$dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but '/dev/$scsi_dev' is the last attached unit."\\n
        perr \\n"$scsi_str"\\n
        besure || errexit
    else
        echo "$scsi_str"
    fi
}

function check_dmsg_for_last_attached_scsi() {
    find_last_attached_scsi_unit     # producer
    check_last_attached_scsi_unit $1 # user
    scsi_str=""; scsi_dev=""         # consumer
}

time='time -freal:%es\n'

function timereal() {
    local time=${time:-time -freal:%es\n}
    ( eval "${@:-false}" || echo "real:error($?)" )  \
         | $time cat 2>&1 | grep -e "real:."
}

function umount_all() {
    local ret=0 i; for i in 1 2 3; do
        umount ${src} ${dst} ${mem} /dev/${dev}* ||:
    done 2>/dev/null
}

################################################################################

trap 'printf "\n\n"; exit 1' INT

declare -i extfs=0 usrmn=0

if is_menu_mode; then
    usrmn=1; set --
else
    iso=${1:-}
fi
dev=${2:-}
if [ "x$3" == "x--ext4-install" ]; then
    extfs=4
    shift
fi
kmp=${3:-}
extfs=${4:+4}
if ! is_real_porteus; then
    extfs=4
fi

str=$(search "$kernelargs_filename" ||:)
kargs=${str:+$(cat "$str" 2>/dev/null ||:)}

sve=$persistnce_filename
bgi=$background_filename
bsi=$bootscreen_filename
cfg=$porteus_config_path
mbr=$usbsk_init_filename

if ! is_menu_mode; then
    test -b "/dev/$dev" || dev=$(basename "$dev")
    test -b "/dev/$dev" || missing "${dev:+/dev/}${dev:-block_device}"
    test -r "$iso" || iso="$wdr/$iso"
    test -r "$iso" || missing "$iso"
fi

test -r "$bsi" || bsi="$wdr/$bsi"
test -f "$bsi" || bsi=""

test -r "$bgi" || bgi="$wdr/$bgi"
test -f "$bgi" || bgi=""

test -r "$mbr" || mbr="$wdr/$mbr"
test -r "$mbr" || missing "$mbr"

if ! amiroot; then
    printf \\n"WARNING: script '$shs' ${dev:+for '/dev/$dev' }requires root priviledges (devel:${DEVEL:-0}) (menu:$usrmn)."\\n
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    isdevel || { amiroot || sudo -k; }
    is_menu_mode && set -- "--user-menu"
    exec sudo -E bash $0 "$@" # exec replaces this process, no return from here
    perr \\n"ERROR: exec fails or a bug hits here, abort!"\\n
    errexit -1
fi

str="/proc/sys/kernel/sysrq"
if test -e $str && echo s >$str; then
    :
else
    nice -19 sync & # RAF: a wait expects to join with this process in background
    sync_pid=$!
fi 2>/dev/null

str=${usrmn/1/user menu mode active}
str=${str/0/(none)}
tfs=${extfs/0/(live)}
tfs=${tfs/4/(inst)}

echo "
Executing shell script from: $wdr
       current working path: $PWD
           script file name: $shs
              with oprtions: ${@:-$str}
              kern. cmdline: ${kargs:-(none)}
                    by user: ${SUDO_USER:+$SUDO_USER as }${USER}
                    variant: ${porteus} ${tfs}
                      devel: ${DEVEL:-unset}"

if is_menu_mode; then
    # RAF: selecting the device by insertion is the most user-friendly way to go
    while true; do
        find_last_attached_scsi_unit
        test -b /dev/$scsi_dev && break
        echo
        read -p "Waiting for the USB stick insertion, press ENTER to continue";
        sleep 1
    done
    echo
    echo "$scsi_str"
    agree "This above is the last unit attached, select it" || usage errexit
    dev=$scsi_dev

    # RAF: auto-selection for ISO, priority: 1. folder; 2. newest
    for d in . "${store_dirn}" "$wdr"; do
        iso=$(command ls -1t "$d"/*.iso "$d"/*.ISO 2>/dev/null ||:)
        test -n "$iso" && break
    done
    # RAF, TODO: if many ISO found, let the user choose among them
    iso=$(echo "$iso" | head -n1)
    test -r "$iso" || missing "ISO:${iso:- not found}"
    agree "Is this '$iso' the ISO file you want use" || usage errexit

    while is_real_porteus; do
        if agree "Do you want an EXT4 installation"; then
            extfs=4; break
        elif agree "Do you want a LIVE for sporadic use" ; then
            extfs=0; break
        fi
    done

    echo; read -p \
"Please provide the 2-letter keyboard language,
or press ENTER for leave the current settings: " kmp
fi

# Deciding about keyboard layout
test -n "$kmp" && kargs="kmap=$kmp ${kargs}"

# Deciding about output redirection
redir="/dev/null"; isdevel && redir="/dev/stdout"

################################################################################
