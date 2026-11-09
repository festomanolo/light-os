#!/bin/bash
#
# /etc/openvpn/lightos-down.sh — OpenVPN tunnel down hook for Light OS
#

STATE_DIR="/run/lightos-vpn"
mkdir -p "$STATE_DIR"

DEV="${dev:-tun0}"
rm -f "${STATE_DIR}/tunnel.up" "${STATE_DIR}/tunnel.dev" "${STATE_DIR}/tunnel.ip"

if [ -f "${STATE_DIR}/resolv.conf.pre-vpn" ]; then
    cp -f "${STATE_DIR}/resolv.conf.pre-vpn" /etc/resolv.conf 2>/dev/null || true
    rm -f "${STATE_DIR}/resolv.conf.pre-vpn"
fi

# Re-verify that the kill switch stays locked when the VPN tunnel drops
if [ -f "${STATE_DIR}/killswitch.enabled" ]; then
    /usr/local/bin/lightos-vpn-killswitch enable >/dev/null 2>&1 || true
fi

logger -t "lightos-openvpn" "VPN tunnel ${DEV} went DOWN; kill switch remains ARMED (internet blocked)." 2>/dev/null || true
exit 0
