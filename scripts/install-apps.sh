#!/usr/bin/env bash
# Install Termux and Termux:X11 (GitHub builds, checksum-verified) on the
# attached phone and let Termux unpack its bootstrap.
#
# Replaces any existing Termux, which deletes its data: Play Store / F-Droid
# builds are signed differently and are not debuggable, and the rest of this
# repo drives Termux through `run-as`.
set -euo pipefail
cd "$(dirname "$0")/.."

# The apps come from this repo's "apps-1" release: unmodified copies of the
# official GitHub builds (Termux 0.118.3, Termux:X11 nightly at fa3a8b4 in its
# sharedUid flavour, Termux:Widget 0.15.0), mirrored so the install does not
# depend on upstream's rolling links, with their upstream checksums. The
# sharedUid Termux:X11 runs inside the Termux process (same uid, same cpuset),
# so Android keeps the VM on all cores while Termux:X11 is on screen; the
# regular build gets its own uid, and Termux, and the VM with it, count as a
# background app whenever Termux:X11 is in front.
APPS=https://github.com/lalomorales22/Omarchy-mobile/releases/download/apps-1
TERMUX_APK=termux-app-v0.118.3-arm64-v8a.apk
TERMUX_SHA=72fdb596045116bf5ba1b5bdf5b26fddb9acc0bd074ad9f2da9eb0ae85e83a4e
X11_APK=termux-x11-1.03.01-fa3a8b4-sharedUid.apk
X11_SHA=cd72ac672bc51ecd6f81e04d5941e05fe1db325f0c3fe97ad4c8729ecab24187
WIDGET_APK=termux-widget-v0.15.0.apk
WIDGET_SHA=780ae459be479bedef2146eb00f7bc79f2a4f89dba2bffa7b55c470165bc66ed

mkdir -p .cache/apk && cd .cache/apk

fetch() { # file sha
  [ -f "$1" ] && echo "$2  $1" | shasum -a 256 -c >/dev/null 2>&1 && return 0
  curl -fL -o "$1" "$APPS/$1"
  echo "$2  $1" | shasum -a 256 -c
}
fetch "$TERMUX_APK" "$TERMUX_SHA"
fetch "$X11_APK" "$X11_SHA"
fetch "$WIDGET_APK" "$WIDGET_SHA"

# Play Protect's "verify apps over USB" rejects sideloaded debug builds.
adb shell settings put global verifier_verify_adb_installs 0

# Keep Android from killing the VM: QEMU is a busy child process of Termux,
# which Android 12+ kills as a "phantom process", and battery optimisation
# freezes apps in the background while Termux:X11 is in front.
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell device_config set_sync_disabled_for_tests persistent
adb shell device_config put activity_manager max_phantom_processes 2147483647
for pkg in com.termux com.termux.x11; do
  adb shell dumpsys deviceidle whitelist +$pkg >/dev/null
  adb shell cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow
done
# A home-screen icon starts Termux from the background, which Android only
# allows with "display over other apps"; the notification keeps it running.
adb shell appops set com.termux SYSTEM_ALERT_WINDOW allow
adb shell pm grant com.termux android.permission.POST_NOTIFICATIONS || true

if adb shell pm list packages com.termux | grep -qx package:com.termux; then
  if ! adb shell 'run-as com.termux true' 2>/dev/null; then
    echo "Replacing the installed (non-debuggable) Termux; its data will be lost."
    adb uninstall com.termux
  fi
fi
adb install -r "$TERMUX_APK"
# A Termux:X11 that was installed with its own uid cannot update to the shared
# one; it has to go first (its settings are re-applied by the launcher).
if adb shell pm list packages com.termux.x11 | grep -qx package:com.termux.x11 &&
   ! adb shell dumpsys package com.termux.x11 | grep -q 'sharedUser=.*com.termux/'; then
  echo "Replacing the standalone Termux:X11 with the shared-uid build."
  adb uninstall com.termux.x11
fi
adb install -r "$X11_APK"
adb install -r "$WIDGET_APK"

adb shell am start -n com.termux/.app.TermuxActivity >/dev/null
for _ in $(seq 1 40); do
  adb shell 'run-as com.termux test -x files/usr/bin/bash' 2>/dev/null && { echo "Termux ready"; exit 0; }
  sleep 3
done
echo "Termux did not finish bootstrapping; open it on the phone and check" >&2
exit 1
