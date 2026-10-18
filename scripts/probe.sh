#!/usr/bin/env bash
# Fingerprint the attached Android phone and write devices/<id>/probe.md.
# Read-only: changes nothing on the phone. Needs USB debugging authorised.
#
#   scripts/probe.sh            # one phone attached
#   ANDROID_SERIAL=XYZ scripts/probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."

prop() { adb shell getprop "$1" | tr -d '\r'; }
sh1() { adb shell "$1" 2>&1 | tr -d '\r'; }

adb get-state >/dev/null

brand=$(prop ro.product.brand | tr '[:upper:]' '[:lower:]')
model=$(prop ro.product.model)
device=$(prop ro.product.device)
id="${brand}-${device}-$(echo "$model" | tr '[:upper:]' '[:lower:]')"
out="devices/$id"
mkdir -p "$out"

locked=$(prop ro.boot.flash.locked)
oem_supported=$(prop ro.oem_unlock_supported)
vm=$(prop ro.boot.hypervisor.vm.supported)
kvm=$(sh1 'test -e /dev/kvm && echo yes || echo no')

# Tiers this phone can reach (see docs/tiers.md).
native="blocked (bootloader locked, no OEM unlock)"
if [ "$locked" = "0" ]; then native="possible (bootloader unlocked)"
elif [ "$oem_supported" = "1" ]; then native="possible after OEM unlock"; fi
vmtier="emulated (TCG, no KVM)"
[ "$kvm" = "yes" ] || [ "$vm" = "1" ] && vmtier="accelerated (KVM/AVF available)"

{
  echo "# $(prop ro.product.manufacturer) $model ($device)"
  echo
  echo "Probed $(date -u +%Y-%m-%d) with \`scripts/probe.sh\`."
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Model | \`$model\` |"
  echo "| Codename | \`$device\` / \`$(prop ro.product.name)\` |"
  echo "| SoC | \`$(prop ro.soc.manufacturer) $(prop ro.soc.model)\` (\`$(prop ro.board.platform)\`) |"
  echo "| GPU | $(sh1 'dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "^GLES:"' | sed 's/^GLES: //; s/ (GIT.*//') |"
  echo "| RAM | $(sh1 'grep MemTotal /proc/meminfo' | awk '{printf "%.1f GB", $2/1048576}') |"
  echo "| Android | $(prop ro.build.version.release) (SDK $(prop ro.build.version.sdk)), patch $(prop ro.build.version.security_patch) |"
  echo "| Build | \`$(prop ro.build.display.id)\` |"
  echo "| Carrier/CSC | \`$(prop ro.csc.sales_code)\` |"
  echo "| Kernel | \`$(sh1 'uname -r')\` |"
  echo "| Bootloader locked | \`${locked:-?}\` (verified boot: \`$(prop ro.boot.verifiedbootstate)\`) |"
  echo "| OEM unlock supported | \`${oem_supported:-not reported}\` |"
  echo "| KVM / AVF VMs | \`$kvm\` / \`${vm:-no}\` |"
  echo
  echo "## Reachable tiers"
  echo
  echo "- **container**: yes (any arm64 Android 7+)"
  echo "- **vm**: $vmtier"
  echo "- **native**: $native"
} > "$out/probe.md"

echo "wrote $out/probe.md"
cat "$out/probe.md"
