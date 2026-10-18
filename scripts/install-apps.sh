#!/usr/bin/env bash
# Install Termux and Termux:X11 (GitHub builds, checksum-verified) on the
# attached phone and let Termux unpack its bootstrap.
#
# Replaces any existing Termux, which deletes its data: Play Store / F-Droid
# builds are signed differently and are not debuggable, and the rest of this
# repo drives Termux through `run-as`.
set -euo pipefail
cd "$(dirname "$0")/.."

TERMUX_TAG=v0.118.3
TERMUX_APK="termux-app_${TERMUX_TAG}+github-debug_arm64-v8a.apk"
TERMUX_SHA=72fdb596045116bf5ba1b5bdf5b26fddb9acc0bd074ad9f2da9eb0ae85e83a4e
# Termux:X11 only publishes a rolling "nightly"; its digest comes from the API.
# The sharedUid build runs inside the Termux process (same uid, same cpuset),
# so Android keeps the VM on all cores while Termux:X11 is on screen. The
# regular build gets its own uid, and Termux, and the VM with it, count as a
# background app whenever Termux:X11 is in front.
X11_API=https://api.github.com/repos/termux/termux-x11/releases/tags/nightly
X11_APK=termux-x11-universal-sharedUid-debug.apk
# Termux:Widget (home-screen icon) must share the Termux build's signing key.
WIDGET_TAG=v0.15.0
WIDGET_APK="termux-widget-app_${WIDGET_TAG}+github.debug.apk"
WIDGET_SHA=780ae459be479bedef2146eb00f7bc79f2a4f89dba2bffa7b55c470165bc66ed

mkdir -p .cache/apk && cd .cache/apk

curl -fL -o termux.apk "https://github.com/termux/termux-app/releases/download/$TERMUX_TAG/${TERMUX_APK//+/%2B}"
echo "$TERMUX_SHA  termux.apk" | shasum -a 256 -c

x11_sha=$(curl -fsSL "$X11_API" | jq -r --arg n "$X11_APK" '.assets[] | select(.name==$n) | .digest' | sed 's/^sha256://')
curl -fL -o termux-x11.apk "https://github.com/termux/termux-x11/releases/download/nightly/$X11_APK"
echo "$x11_sha  termux-x11.apk" | shasum -a 256 -c

curl -fL -o termux-widget.apk "https://github.com/termux/termux-widget/releases/download/$WIDGET_TAG/${WIDGET_APK//+/%2B}"
echo "$WIDGET_SHA  termux-widget.apk" | shasum -a 256 -c

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
adb install -r termux.apk
# A Termux:X11 that was installed with its own uid cannot update to the shared
# one; it has to go first (its settings are re-applied by the launcher).
if adb shell pm list packages com.termux.x11 | grep -qx package:com.termux.x11 &&
   ! adb shell dumpsys package com.termux.x11 | grep -q 'sharedUser=.*com.termux/'; then
  echo "Replacing the standalone Termux:X11 with the shared-uid build."
  adb uninstall com.termux.x11
fi
adb install -r termux-x11.apk
adb install -r termux-widget.apk

adb shell am start -n com.termux/.app.TermuxActivity >/dev/null
for _ in $(seq 1 40); do
  adb shell 'run-as com.termux test -x files/usr/bin/bash' 2>/dev/null && { echo "Termux ready"; exit 0; }
  sleep 3
done
echo "Termux did not finish bootstrapping; open it on the phone and check" >&2
exit 1
