#!/usr/bin/env bash
# Boot the Omarchy VM on the attached phone and bring Termux:X11 to the front.
# Runs in the foreground: the VM lives as long as this adb session does.
#
#   scripts/vm-up.sh                    # Adreno-accelerated virgl
#   OMARCHY_VM_GL=llvmpipe scripts/vm-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

adb shell svc power stayon true  # Macs often enumerate as an AC charger, not USB
adb shell am start -n com.termux.x11/.MainActivity >/dev/null

env_lines=""
for v in OMARCHY_VM_GL OMARCHY_VM_RAM OMARCHY_VM_CPUS OMARCHY_VM_CPU OMARCHY_VM_SIZE OMARCHY_VM_ORIENTATION OMARCHY_VM_DEBUG; do
  [ -n "${!v:-}" ] && env_lines+="export $v=${!v}"$'\n'
done

{ printf '%s' "$env_lines"; cat phone/start-vm.sh; } | scripts/termux-run.sh
