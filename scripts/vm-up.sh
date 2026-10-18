#!/usr/bin/env bash
# Boot the Omarchy VM on the attached phone and bring Termux:X11 to the front.
# Launched this way (over adb rather than from the home-screen icon), QEMU gets
# every CPU core. Runs in the foreground: the VM lives as long as this adb
# session does.
#
#   scripts/vm-up.sh [portrait|landscape]
#   OMARCHY_VM_GL=llvmpipe scripts/vm-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The phone runs its installed launcher; refresh it from this checkout first.
scripts/install-launcher.sh >/dev/null

adb shell svc power stayon true  # Macs often enumerate as an AC charger, not USB
adb shell am start -n com.termux.x11/.MainActivity >/dev/null

env_lines=""
for v in OMARCHY_VM_GL OMARCHY_VM_RAM OMARCHY_VM_CPUS OMARCHY_VM_CPU OMARCHY_VM_SIZE OMARCHY_VM_ORIENTATION OMARCHY_VM_DEBUG; do
  [ -n "${!v:-}" ] && env_lines+="export $v=${!v}"$'\n'
done

printf '%sexec bash "$HOME/omarchy-vm/start-vm.sh" %s\n' "$env_lines" "${1:-}" | scripts/termux-run.sh
