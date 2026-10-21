#!/usr/bin/env bash
# Read-only diagnostics for the TP-Link AC1300 (RTL8822BU) offline Wi-Fi package.
# Safe to run any time, before or after installation. Usage: ./check.sh
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_SRC="$PKG_DIR/firmware/rtw88/rtw8822b_fw.bin"
MODULE="rtw88_8822bu"
KERNEL="$(uname -r)"
KMAJ="${KERNEL%%.*}"
KREST="${KERNEL#*.}"; KMIN="${KREST%%.*}"

K_OK=0
if [ "$KMAJ" -gt 6 ] || { [ "$KMAJ" -eq 6 ] && [ "$KMIN" -ge 7 ]; }; then
  K_OK=1
fi

ok()   { printf '  [ OK ] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; }
head2(){ printf '\n== %s ==\n' "$1"; }

head2 "1. Kernel"
echo "  running kernel: $KERNEL"
if [ "$K_OK" -eq 1 ]; then
  ok "kernel >= 6.7 ships the in-tree rtw88 USB driver (RTL8822BU is supported)"
else
  bad "kernel $KERNEL is older than 6.7 -> in-tree driver missing, firmware alone will NOT be enough"
  echo "         fix: boot a >=6.7 kernel (e.g. sudo apt install linux-generic-hwe-24.04) or use an out-of-tree DKMS driver"
fi

head2 "2. Kernel modules"
if modinfo -F depends "$MODULE" >/dev/null 2>&1; then
  ok "$MODULE present (depends: $(modinfo -F depends "$MODULE"))"
  owner="$(dpkg -S "/lib/modules/$KERNEL/kernel/drivers/net/wireless/realtek/rtw88/$MODULE.ko.zst" 2>/dev/null | cut -d: -f1)"
  [ -n "$owner" ] && echo "         provided by package: $owner"
else
  bad "$MODULE not found for $KERNEL"
  echo "         it ships in linux-modules-extra-$KERNEL -> see fetch-debs.sh, or boot another kernel"
fi
for m in rtw88_usb rtw88_8822b rtw88_core mac80211 cfg80211; do
  if modinfo "$m" >/dev/null 2>&1; then ok "dependency module $m available"; else warn "module $m missing"; fi
done

head2 "3. Firmware file"
for dir in /lib/firmware /usr/lib/firmware; do
  f="$dir/rtw88/rtw8822b_fw.bin"
  if [ -e "$f" ]; then
    ok "found plain $f"
  elif [ -e "$f.zst" ]; then
    ok "found compressed $f.zst (kernel >= 6.3 with FW_LOADER_COMPRESS_ZSTD loads it directly)"
  else
    warn "$f(.zst) not present in $dir"
  fi
done
if [ -f "$FW_SRC" ]; then
  echo "  bundled firmware sha256: $(sha256sum "$FW_SRC" | cut -c1-16)..."
else
  warn "bundled firmware $FW_SRC missing (package incomplete)"
fi
if [ -e /lib/firmware/regulatory.db ]; then
  ok "regulatory.db present (allowed channels / 5 GHz country rules)"
else
  warn "regulatory.db missing -> wireless-regdb package is bundled in ./debs"
fi

head2 "4. USB dongle"
if command -v lsusb >/dev/null 2>&1; then
  line="$(lsusb 2>/dev/null | grep -iE '2357:(0138|0115|0116|0117|012d|012e)|0bda:(8822|b822)' || true)"
  if [ -n "$line" ]; then ok "device visible: $line"; else bad "no RTL8822BU dongle in lsusb -> plug it in (try a USB 3.0 port)"; fi
else
  warn "lsusb not installed, cannot check USB IDs"
fi

head2 "5. Wireless interfaces"
if command -v iw >/dev/null 2>&1; then
  n="$(iw dev 2>/dev/null | grep -c 'Interface' || true)"
  echo "  interfaces via iw: $n"
  iw dev 2>/dev/null | sed 's/^/    /'
else
  warn "iw not installed yet (the package provides it)"
fi
echo "  wlan-ish netdevs:"
ls -d /sys/class/net/wl* 2>/dev/null | sed 's/^/    /' || echo "    (none)"
for d in /sys/bus/usb/drivers/rtw_8822bu /sys/bus/usb/drivers/*8822bu*; do
  [ -d "$d" ] || continue
  echo "  driver dir $d:"
  echo "    bound devices: $(find "$d" -maxdepth 1 -name '[0-9]*-[0-9]*' 2>/dev/null | wc -l)"
  echo "    net interfaces: $(ls -d "$d"/*/net/* 2>/dev/null | sed 's#.*/##' | tr '\n' ' ' || echo none)"
done

head2 "6. Radio switches"
if command -v rfkill >/dev/null 2>&1; then
  rfkill list 2>/dev/null | sed 's/^/    /' || true
else
  warn "rfkill not installed"
fi

head2 "7. Userspace tools"
for t in nmcli wpa_cli iw iwconfig dhclient; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else warn "$t missing"; fi
done
if command -v NetworkManager >/dev/null 2>&1 || systemctl is-active NetworkManager >/dev/null 2>&1; then
  ok "NetworkManager available (can manage the Wi-Fi connection)"
else
  warn "NetworkManager not found -> use wpa_supplicant + dhclient manually"
fi

head2 "8. Kernel log (needs root)"
if [ "$(id -u)" -eq 0 ]; then
  logs="$( (dmesg 2>/dev/null || journalctl -k --no-pager 2>/dev/null) | grep -iE 'rtw88|rtw_|8822b|firmware.*rtw' | tail -15 || true)"
  if [ -n "$logs" ]; then echo "$logs" | sed 's/^/    /'; else warn "no rtw88 lines in the kernel log yet"; fi
else
  echo "  skipped (run: sudo ./check.sh)"
fi

head2 "Summary"
if [ "$K_OK" -eq 1 ] && modinfo "$MODULE" >/dev/null 2>&1; then
  echo "  This machine can run the dongle with the in-tree driver."
  echo "  Next step:  sudo ./install.sh"
else
  echo "  Prerequisites are NOT met (see the FAIL lines above)."
  echo "  Run 'sudo ./check.sh' after fixing them, then 'sudo ./install.sh'."
fi
exit 0
