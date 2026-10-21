#!/usr/bin/env bash
# Persistent power-management fix for TP-Link 2357:0138 using rtw88_8822bu.
# Usage: sudo bash ./fix-persistence.sh
set -euo pipefail

if (( EUID != 0 )); then
  echo 'Run: sudo bash ./fix-persistence.sh' >&2
  exit 1
fi
modinfo rtw88_8822bu >/dev/null
modinfo -p rtw88_core | grep -q '^disable_lps_deep:'

backup_dir="/var/lib/tplink-ac1300-fix/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$backup_dir"
save_original() {
  if [[ -e "$1" ]]; then cp -a --parents "$1" "$backup_dir/"; fi
}
for file in /etc/modprobe.d/90-tplink-ac1300.conf \
            /etc/NetworkManager/conf.d/90-tplink-ac1300.conf \
            /etc/udev/rules.d/90-tplink-ac1300.rules; do
  save_original "$file"
done

cat > /etc/modprobe.d/90-tplink-ac1300.conf <<'EOF'
# Avoid firmware failures leaving low-power state on RTL8822BU.
options rtw88_core disable_lps_deep=Y
EOF
cat > /etc/NetworkManager/conf.d/90-tplink-ac1300.conf <<'EOF'
# Default for connections using this TP-Link adapter, including new profiles.
[connection-tplink-ac1300]
match-device=driver:rtw88_8822bu
wifi.powersave=2
EOF
cat > /etc/udev/rules.d/90-tplink-ac1300.rules <<'EOF'
# Keep only the TP-Link AC1300 USB device awake across boots and replugging.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2357", ATTR{idProduct}=="0138", TEST=="power/control", ATTR{power/control}="on"
EOF
chmod 0644 /etc/modprobe.d/90-tplink-ac1300.conf \
           /etc/NetworkManager/conf.d/90-tplink-ac1300.conf \
           /etc/udev/rules.d/90-tplink-ac1300.rules

udevadm control --reload-rules
nmcli general reload conf
if [[ -w /sys/module/rtw88_core/parameters/disable_lps_deep ]]; then
  echo Y > /sys/module/rtw88_core/parameters/disable_lps_deep
fi
for dev in /sys/bus/usb/devices/*; do
  [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]] || continue
  if [[ $(cat "$dev/idVendor") == 2357 && $(cat "$dev/idProduct") == 0138 ]]; then
    echo on > "$dev/power/control"
    for net in "$dev"/*/net/*; do
      [[ -d "$net" ]] || continue
      iw dev "${net##*/}" set power_save off
    done
  fi
done

# Copy the module option into existing early-boot images too.
# Future kernel installations pick up /etc/modprobe.d automatically.
update-initramfs -u -k all
echo "Persistent settings installed. Previous files saved in $backup_dir"
