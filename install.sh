#!/usr/bin/env bash
# Omarchy Mobile installer: a USB-connected Android phone to Omarchy, in one go.
# Every step is safe to re-run, so after a failure just run this again.
#
#   ./install.sh                 # landscape
#   ./install.sh --portrait
#   ./install.sh --yes           # answer yes, including to replacing a non-GitHub Termux
set -euo pipefail
cd "$(dirname "$0")"

orientation=landscape
assume_yes=0
for arg in "$@"; do
  case $arg in
    --portrait) orientation=portrait ;;
    --landscape) orientation=landscape ;;
    --yes|-y) assume_yes=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
confirm() {
  [ "$assume_yes" = 1 ] && return 0
  local reply
  read -r -p "$1 [y/N] " reply </dev/tty
  [[ $reply == [yY]* ]]
}
prop() { adb shell getprop "$1" | tr -d '\r'; }

step "Checking this computer"
if [ "$(uname)" = Darwin ]; then hint="brew install"; else hint="sudo apt install"; fi
command -v adb >/dev/null || die "adb is missing: $([ "$(uname)" = Darwin ] && echo 'brew install --cask android-platform-tools' || echo 'sudo apt install adb')"
command -v curl >/dev/null || die "curl is missing: $hint curl"
command -v jq >/dev/null || die "jq is missing: $hint jq"
command -v shasum >/dev/null || die "shasum is missing: $hint perl"

step "Finding the phone"
devices=$(adb devices | tail -n +2 | grep -v '^\s*$' || true)
if [ -z "${ANDROID_SERIAL:-}" ] && [ "$(echo "$devices" | grep -c .)" -gt 1 ]; then
  die "several phones are connected; pick one with ANDROID_SERIAL=<serial> ./install.sh"$'\n'"$devices"
fi
case "$(echo "$devices" | awk '{print $2}' | head -1)" in
  device) ;;
  unauthorized) die "the phone is asking for permission: unlock it, tick \"Always allow\", tap Allow, then run this again" ;;
  "") die "no phone found. On the phone: Settings > About phone > Software information, tap \"Build number\" 7 times; then Settings > Developer options > USB debugging on. Connect the cable and run this again." ;;
  *) die "the phone is not ready: $devices" ;;
esac

abi=$(prop ro.product.cpu.abi)
[ "$abi" = arm64-v8a ] || die "this needs a 64-bit ARM phone (found $abi)"
ram_gb=$(adb shell 'grep MemTotal /proc/meminfo' | awk '{printf "%d", $2/1048576 + 0.5}')
free_gb=$(adb shell 'df -k /data' | tail -1 | awk '{printf "%d", $4/1048576}')
gpu=$(adb shell 'dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "^GLES:"' | tr -d '\r' | sed 's/^GLES: //; s/, OpenGL.*//')
echo "$(prop ro.product.manufacturer) $(prop ro.product.model), Android $(prop ro.build.version.release), ${ram_gb} GB RAM, ${free_gb} GB free, GPU: $gpu"
[ "$free_gb" -ge 16 ] || die "Omarchy needs about 16 GB free on the phone (found ${free_gb} GB)"
[ "$ram_gb" -ge 6 ] || warn "with ${ram_gb} GB of RAM the VM will be cramped; 8 GB is recommended"
[[ $gpu == *Adreno* ]] || warn "no Adreno GPU: graphics will fall back to software and be much slower (set OMARCHY_VM_GL=llvmpipe)"
scripts/probe.sh >/dev/null && echo "device report: devices/$(ls -t devices | grep -v TEMPLATE | head -1)/probe.md"

if adb shell 'run-as com.termux true' 2>/dev/null; then
  if adb shell 'run-as com.termux sh -c "pgrep -f qemu-system-aarch64"' >/dev/null 2>&1; then
    die "Omarchy is running on the phone; shut it down from its menu first (reinstalling the apps would kill it)"
  fi
elif adb shell pm list packages com.termux | tr -d '\r' | grep -qx package:com.termux; then
  echo "Termux is installed from the Play Store or F-Droid. Omarchy Mobile needs the GitHub build,"
  echo "so that Termux is replaced and everything inside it is deleted."
  confirm "Replace Termux?" || die "stopped; nothing was changed"
fi

adb shell svc power stayon true
echo "Keep the phone unlocked until this finishes. If Android shows an \"App Compatibility\""
echo "warning about a debuggable app, tap \"Don't Show Again\"."

step "1/4  Termux, Termux:X11 and Termux:Widget"
scripts/install-apps.sh

step "2/4  Termux packages (X11, QEMU dependencies, GPU drivers)"
scripts/termux-run.sh phone/01-termux-base.sh

step "3/4  Omarchy disk image (about 3 GB download, unpacked to a 20 GB sparse file)"
scripts/termux-run.sh phone/10-vm-image.sh

step "4/4  Launcher and home-screen icon"
echo "echo $orientation > \$HOME/omarchy-vm/orientation" | scripts/termux-run.sh
scripts/install-launcher.sh --pin

step "Done"
cat <<EOF
Tap the Omarchy icon on the phone (Samsung may put it on a new home-screen page).
You can unplug the phone now.

The first boot takes about half an hour: Omarchy creates this machine's keys
and finishes its hardware setup on an emulated CPU. Then it asks for your
keyboard, name and password, and starts the desktop. Later boots take minutes.

SUPER on the key bar is Omarchy's main key: SUPER then the return key opens a
terminal, SUPER then SPACE opens the launcher. In Termux, "omarchy portrait" or
"omarchy landscape" switches orientation. Stuck? See docs/debugging.md.
EOF
