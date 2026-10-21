#!/usr/bin/env bash
# Offline installer for the TP-Link AC1300 / Archer T3U Plus USB Wi-Fi dongle
# (Realtek RTL8822BU, USB ID 2357:0138) on Ubuntu 24.04 (kernel >= 6.8).
#
#   sudo ./install.sh              # install firmware + missing tools, verify link
#   sudo ./install.sh --dry-run    # show what would happen, make no changes
#   sudo ./install.sh --fw-only    # only place the firmware file
#
# It only touches: /lib/firmware/rtw88/, dpkg packages from ./debs/, and the
# driver binding of the dongle itself. Uninstall info is printed at the end.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_SRC="$PKG_DIR/firmware/rtw88/rtw8822b_fw.bin"
FW_DST_DIR="/lib/firmware/rtw88"
MODULE="rtw88_8822bu"
DRY=0; FW_ONLY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --fw-only) FW_ONLY=1 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
do_it() { if [ "$DRY" -eq 1 ]; then printf '  (dry-run) %s\n' "$*"; else eval "$@"; fi; }

[ -f "$FW_SRC" ] || { say "FATAL: $FW_SRC not found - package incomplete"; exit 1; }
if [ "$DRY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  say "FATAL: run with root:  sudo ./install.sh"; exit 1
fi

KERNEL="$(uname -r)"
say "== Target: kernel $KERNEL, module $MODULE, firmware $(sha256sum "$FW_SRC" | cut -c1-16)..."

if ! modinfo "$MODULE" >/dev/null 2>&1; then
  say "FATAL: kernel module $MODULE is not available for $KERNEL."
  say "  On Ubuntu 24.04 it lives in the package linux-modules-extra-<kernel> (desktop installs have it,"
  say "  server/minimal installs often do not). Options:"
  say "    a) GRUB menu -> boot the generic 6.8 kernel that has linux-modules-extra installed"
  say "    b) copy linux-modules-extra-\$KERNEL.deb (and its deps linux-modules-\$KERNEL, wireless-regdb)"
  say "       from an online machine, then: sudo dpkg -i *.deb   # run ./fetch-debs.sh on the online box"
  say "  Kernels older than 6.7 have no in-tree RTL8822BU driver at all - this package does not cover that."
  exit 1
fi

say; say "== 1. Firmware"
do_it "mkdir -p '$FW_DST_DIR'"
if [ -f "$FW_DST_DIR/rtw8822b_fw.bin" ] && cmp -s "$FW_SRC" "$FW_DST_DIR/rtw8822b_fw.bin"; then
  say "  already installed and identical, skipped"
else
  if [ -f "$FW_DST_DIR/rtw8822b_fw.bin" ]; then
    do_it "cp -a '$FW_DST_DIR/rtw8822b_fw.bin' '$FW_DST_DIR/rtw8822b_fw.bin.bak-$(date +%Y%m%d%H%M%S)' 2>/dev/null || true"
  fi
  do_it "install -m 0644 '$FW_SRC' '$FW_DST_DIR/rtw8822b_fw.bin'"
  say "  -> $FW_DST_DIR/rtw8822b_fw.bin"
fi

if [ "$FW_ONLY" -eq 0 ]; then
  say; say "== 2. Userspace tools (only what is missing)"
  declare -A DEB_FOR=( [iw]="iw" [wpa_cli]="wpasupplicant" [iwconfig]="wireless-tools libiw30t64" )
  for cmd in "${!DEB_FOR[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      say "  $cmd present"
      continue
    fi
    for pkg in ${DEB_FOR[$cmd]}; do
      deb="$(ls "$PKG_DIR"/debs/${pkg}_*.deb 2>/dev/null | head -1)"
      if [ -z "$deb" ]; then say "  WARN: no bundled deb for $pkg"; continue; fi
      if [ "$DRY" -eq 1 ]; then do_it "dpkg -i '$deb'"; continue; fi
      if dpkg -i "$deb" >/dev/null 2>&1; then say "  installed $(basename "$deb")"
      else say "  WARN: dpkg failed for $(basename "$deb") (dependency missing?)"; fi
    done
  done
  # regulatory.db drives the allowed Wi-Fi channels (matters on 5 GHz)
  if [ ! -e /lib/firmware/regulatory.db ]; then
    deb="$(ls "$PKG_DIR"/debs/wireless-regdb_*.deb 2>/dev/null | head -1)"
    if [ -n "$deb" ]; then
      if [ "$DRY" -eq 1 ]; then do_it "dpkg -i '$deb'"
      elif dpkg -i "$deb" >/dev/null 2>&1; then say "  installed wireless-regdb (regulatory.db)"
      else say "  WARN: wireless-regdb install failed"; fi
    else
      say "  WARN: /lib/firmware/regulatory.db missing and no bundled wireless-regdb deb"
    fi
  else
    say "  regulatory.db present"
  fi
fi

say; say "== 3. Load driver / rebind dongle"
do_it "modprobe '$MODULE' 2>/dev/null || true"
# The USB driver is registered as rtw_8822bu (sysfs name differs from the module name).
DRV_DIR="$(ls -d /sys/bus/usb/drivers/rtw_8822bu /sys/bus/usb/drivers/*8822bu* /sys/bus/usb/drivers/*8822b_u* 2>/dev/null | head -1)"
iface_of() { ls -d "$1"/*/net/* 2>/dev/null | head -1; }
IFACE="$(iface_of "$DRV_DIR")"; IFACE="${IFACE##*/}"
bound=""
[ -n "$DRV_DIR" ] && bound="$(find "$DRV_DIR" -maxdepth 1 -name '[0-9]*-[0-9]*' 2>/dev/null | head -1)"
if [ -n "$IFACE" ]; then
  say "  driver already bound and interface $IFACE exists - no rebind needed"
elif [ -n "$bound" ]; then
  say "  rebinding ${bound##*/} so the driver re-reads the firmware"
  if [ "$DRY" -eq 0 ]; then
    echo "$(basename "$bound")" > "$DRV_DIR/unbind" 2>/dev/null || true
    sleep 2
    echo "$(basename "$bound")" > "$DRV_DIR/bind" 2>/dev/null || true
    sleep 3
  fi
else
  say "  dongle not bound yet - plug it in now (direct USB port, no hub), then re-run this script"
fi

say; say "== 4. Verify"
[ -n "$IFACE" ] || { p="$(iface_of "$DRV_DIR")"; IFACE="${p##*/}"; }
if [ "$DRY" -eq 1 ]; then
  say "  (dry-run) would now bring up the interface and run a scan"
  exit 0
fi
if [ -z "$IFACE" ]; then
  say "  FAIL: no network interface created by $MODULE."
  say "  Run 'sudo ./check.sh' and read section 8 (kernel log) for the exact reason."
  exit 1
fi
rfkill unblock wlan 2>/dev/null || true
do_it "ip link set '$IFACE' up"
say "  interface: $IFACE  ($(cat "/sys/class/net/$IFACE/address" 2>/dev/null))"
if command -v nmcli >/dev/null 2>&1; then
  say "  scanning..."
  nmcli device wifi rescan ifname "$IFACE" >/dev/null 2>&1 || true
  sleep 4
  nmcli -f SSID,CHAN,RATE,SIGNAL,SECURITY device wifi list ifname "$IFACE" --rescan no 2>/dev/null | head -15
  say
  say "  Connect with:"
  say "    sudo nmcli device wifi connect \"<SSID>\" password \"<password>\" ifname $IFACE"
else
  say "  nmcli missing - configure manually with wpa_supplicant, e.g.:"
  say "    sudo wpa_passphrase \"<SSID>\" \"<password>\" | sudo tee /etc/wpa_supplicant.conf"
  say "    sudo wpa_supplicant -i $IFACE -c /etc/wpa_supplicant.conf -B"
  say "    sudo dhclient $IFACE"
fi
say
say "To undo the firmware change: remove $FW_DST_DIR/rtw8822b_fw.bin and restore the .bak- file, then replug."
