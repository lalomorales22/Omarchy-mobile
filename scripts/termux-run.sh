#!/usr/bin/env bash
# Run a script inside the Termux app's environment from the host, over adb.
#
#   scripts/termux-run.sh phone/01-termux-base.sh     # run a file
#   echo 'pkg list-installed' | scripts/termux-run.sh  # run stdin
#
# Requires the Termux *GitHub* build (debuggable), which lets `run-as com.termux`
# drop into the app's uid. Play Store / F-Droid builds are not debuggable.
set -euo pipefail

# With several phones attached, pick one with ANDROID_SERIAL (adb reads it natively).
P=/data/data/com.termux/files

if [ $# -gt 0 ]; then
  exec < "$1"
fi

# run-as starts in the app's data dir with umask 000; Termux uses $HOME and 077.
# The \$VARs expand on the phone: app_process (Termux:X11, termux-am) needs the
# Android runtime's environment, which env -i would otherwise drop.
{ echo 'umask 077; cd "$HOME"'; cat; } | adb shell run-as com.termux "$P/usr/bin/env" -i \
  HOME="$P/home" PREFIX="$P/usr" TMPDIR="$P/usr/tmp" \
  PATH="$P/usr/bin" LANG=en_US.UTF-8 TERM=xterm-256color \
  LD_PRELOAD="$P/usr/lib/libtermux-exec-ld-preload.so" \
  TERMUX_EXEC__SYSTEM_LINKER_EXEC__MODE=disable \
  ANDROID_DATA=/data ANDROID_ROOT=/system \
  'BOOTCLASSPATH=$BOOTCLASSPATH' 'DEX2OATBOOTCLASSPATH=$DEX2OATBOOTCLASSPATH' \
  'SYSTEMSERVERCLASSPATH=$SYSTEMSERVERCLASSPATH' 'ANDROID_ART_ROOT=$ANDROID_ART_ROOT' \
  'ANDROID_I18N_ROOT=$ANDROID_I18N_ROOT' 'ANDROID_TZDATA_ROOT=$ANDROID_TZDATA_ROOT' \
  'ANDROID_ASSETS=$ANDROID_ASSETS' 'EXTERNAL_STORAGE=$EXTERNAL_STORAGE' \
  "$P/usr/bin/bash" -l -s
