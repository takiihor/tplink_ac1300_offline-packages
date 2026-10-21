#!/usr/bin/env bash
# Run this on an INTERNET-CONNECTED Ubuntu 24.04 machine to extend the offline
# package with the kernel-module packages a minimal/server install may lack.
#
#   ./fetch-debs.sh                                # kernel of THIS machine
#   ./fetch-debs.sh 6.8.0-142-generic [amd64|arm64]  # a specific kernel/arch
#
# Output: ./extra-debs/*.deb  -> copy them into the package's debs/ folder.
set -uo pipefail

KERNEL="${1:-$(uname -r)}"
ARCH="${2:-$(dpkg --print-architecture)}"
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/extra-debs"
PKGS=(
  "linux-modules-extra-$KERNEL"
  "linux-modules-$KERNEL"
  "linux-image-unsigned-$KERNEL"
  "wireless-regdb"
)

mkdir -p "$OUT"
echo "Fetching for kernel $KERNEL ($ARCH) into $OUT"
for p in "${PKGS[@]}"; do
  if (cd "$OUT" && apt-get download "$p:$ARCH" >/dev/null 2>&1) ||
     (cd "$OUT" && apt-get download "$p" >/dev/null 2>&1); then
    echo "  OK   $p:$ARCH"
  else
    echo "  SKIP $p:$ARCH (not in the configured archives - check kernel version and arch)"
  fi
done
echo
echo "Result:"
ls -la "$OUT"
echo
echo "Note: linux-modules-extra is ~110 MB and contains drivers for all vendors."
echo "      install.sh only needs it when check.sh reports the module as missing."
