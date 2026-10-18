#!/usr/bin/env bash
# Install the phone-side launcher: an `omarchy` command in Termux and an
# "Omarchy" Termux:Widget shortcut with Omarchy's icon, so the VM starts from
# the phone alone. Re-run after changing phone/start-vm.sh.
#
#   scripts/install-launcher.sh          # install
#   scripts/install-launcher.sh --pin    # also open the "add to home screen" picker
set -euo pipefail
cd "$(dirname "$0")/.."

{
  echo 'mkdir -p "$HOME/omarchy-vm"'
  echo 'cat > "$HOME/omarchy-vm/start-vm.sh" <<'"'"'OMARCHY_START_VM'"'"''
  cat phone/start-vm.sh
  echo 'OMARCHY_START_VM'
  echo 'cat > "$HOME/omarchy-vm/guest-setup.sh" <<'"'"'OMARCHY_GUEST_SETUP'"'"''
  cat phone/guest-setup.sh
  echo 'OMARCHY_GUEST_SETUP'
  cat <<'EOF'
cat > "$PREFIX/bin/omarchy" <<'OMARCHY_BIN'
#!/data/data/com.termux/files/usr/bin/bash
# Boot the Omarchy VM, or bring it back to the front if it is already running.
#   omarchy [portrait|landscape]     see OMARCHY_VM_* in ~/omarchy-vm/start-vm.sh
am start -n com.termux.x11/.MainActivity >/dev/null 2>&1
if pgrep -f "qemu-system-aarch64.*omarchy-vm/omarchy.img" >/dev/null; then
  exit 0
fi
termux-wake-lock
exec bash "$HOME/omarchy-vm/start-vm.sh" "$@"
OMARCHY_BIN
chmod 700 "$PREFIX/bin/omarchy"

# Termux:Widget picks up scripts in ~/.shortcuts and icons in ~/.shortcuts/icons.
mkdir -p "$HOME/.shortcuts/icons"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec omarchy\n' > "$HOME/.shortcuts/Omarchy"
chmod 700 "$HOME/.shortcuts/Omarchy"
curl -fsSL -o "$HOME/.shortcuts/icons/Omarchy.png" https://raw.githubusercontent.com/basecamp/omarchy/HEAD/icon.png
echo "installed: omarchy, ~/.shortcuts/Omarchy"
EOF
} | scripts/termux-run.sh

if [ "${1:-}" = "--pin" ]; then
  # Termux:Widget's shortcut picker; choosing "Omarchy" asks the launcher to pin it.
  adb shell am start -n com.termux.widget/.TermuxCreateShortcutActivity >/dev/null
  echo "On the phone: tap \"Omarchy\", then \"Add\"."
fi
