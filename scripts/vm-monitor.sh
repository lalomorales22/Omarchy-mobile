#!/usr/bin/env bash
# Talk to the running VM's QEMU monitor from the host.
#
#   scripts/vm-monitor.sh 'info status'
#   scripts/vm-monitor.sh screenshot shot.png   # guest framebuffer -> host file
set -euo pipefail
cd "$(dirname "$0")/.."

VM=/data/data/com.termux/files/home/omarchy-vm

monitor() {
  scripts/termux-run.sh <<EOF
command -v socat >/dev/null || apt-get install -y socat >/dev/null 2>&1
{ printf '%s\n' $(printf '%q' "$1"); sleep 1; } |
  socat - UNIX-CONNECT:$VM/monitor.sock | tr -d '\r' | sed '/^QEMU .* monitor/d; /^(qemu)/d'
EOF
}

if [ "${1:-}" = "screenshot" ]; then
  out=${2:-vm-screen.png}
  monitor "screendump $VM/screen.png -f png" >/dev/null
  adb exec-out run-as com.termux cat "$VM/screen.png" > "$out"
  echo "$out"
else
  monitor "${1:?usage: vm-monitor.sh '<monitor command>' | screenshot [file]}"
fi
