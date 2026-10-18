# Runs inside the Omarchy guest as root, early in every boot: start-vm.sh copies
# it to the boot partition and has systemd run it before sysinit.target. It
# fits Omarchy's timeouts to a VM whose CPU is emulated; none of it is needed
# on real hardware.
set -e

conf() { mkdir -p "$(dirname "$1")"; cat >"$1"; }

# systemd waits 90 s for disks and services; under TCG udev alone needs minutes.
conf /etc/systemd/system.conf.d/90-omarchy-mobile.conf <<'EOF'
[Manager]
DefaultDeviceTimeoutSec=600
DefaultTimeoutStartSec=300
EOF

# uwsm gives Hyprland 30 s to start, and waitenv 30 s (its unit timeout and its
# own UWSM_WAIT_VARNAMES_TIMEOUT countdown) to see WAYLAND_DISPLAY. Each takes
# about a minute here.
conf /etc/systemd/user.conf.d/90-omarchy-mobile.conf <<'EOF'
[Manager]
DefaultTimeoutStartSec=300
DefaultEnvironment=UWSM_WAIT_VARNAMES_TIMEOUT=600
EOF
for unit in wayland-wm@ wayland-wm-env@ wayland-session-waitenv; do
  conf "/etc/systemd/user/$unit.service.d/90-omarchy-mobile.conf" <<'EOF'
[Service]
TimeoutStartSec=600
TimeoutStopSec=60
Environment=UWSM_WAIT_VARNAMES_TIMEOUT=600
EOF
done

# Hyprland gives each Lua config (re)load 1.5 s, a compile-time constant
# (LUA_TIMEOUT_CONFIG_RELOAD_MS). Omarchy's config spawns shell commands and
# loads a plugin while it is evaluated, which takes longer than that here: a
# "Your config has errors ... execution timed out" banner, and part of the
# config left unloaded. The constant is a single instruction, `mov w4, #1500`
# (w4 is guardedPCall's timeoutMs). Rewrite it to 15 s, but only where it is
# found exactly once; re-applied by a pacman hook whenever Hyprland updates.
conf /usr/local/bin/omarchy-mobile-patch-hyprland <<'EOF'
#!/usr/bin/python3 -I
import os
import sys

path = "/usr/bin/Hyprland"


def movz_w4(imm):
    return (0x52800000 | imm << 5 | 4).to_bytes(4, "little")


def offsets(data, needle):
    found, i = [], data.find(needle)
    while i != -1:
        if i % 4 == 0:
            found.append(i)
        i = data.find(needle, i + 1)
    return found


data = open(path, "rb").read()
old, new = movz_w4(1500), movz_w4(15000)
hits = offsets(data, old)
if not hits and offsets(data, new):
    sys.exit(0)
if len(hits) != 1:
    print(f"omarchy-mobile: {len(hits)} matches for the Lua reload limit in {path}; leaving it alone")
    sys.exit(0)
patched = data[:hits[0]] + new + data[hits[0] + 4:]
tmp = path + ".omarchy-mobile"
with open(tmp, "wb") as f:
    f.write(patched)
os.chmod(tmp, os.stat(path).st_mode)
os.replace(tmp, path)
print("omarchy-mobile: Hyprland's Lua config reload limit is now 15 s")
EOF
chmod 755 /usr/local/bin/omarchy-mobile-patch-hyprland
conf /etc/pacman.d/hooks/90-omarchy-mobile-hyprland.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/bin/Hyprland

[Action]
Description = Omarchy Mobile: giving Hyprland's Lua config reloads 15 s
When = PostTransaction
Exec = /usr/local/bin/omarchy-mobile-patch-hyprland
EOF
/usr/local/bin/omarchy-mobile-patch-hyprland || true

# If a future Hyprland no longer matches the patch above, retry the reload
# until one fits.
conf /usr/local/bin/omarchy-mobile-settle <<'EOF'
#!/bin/sh
for _ in $(seq 1 15); do
  sleep 60
  errors=$(hyprctl -j configerrors 2>/dev/null) || continue
  case $errors in *"timed out"*) hyprctl reload >/dev/null 2>&1 || true ;; *) exit 0 ;; esac
done
EOF
chmod 755 /usr/local/bin/omarchy-mobile-settle
conf /etc/systemd/user/omarchy-mobile-settle.service <<'EOF'
[Unit]
Description=Omarchy Mobile: retry Hyprland config reloads that hit the Lua time limit
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/omarchy-mobile-settle

[Install]
WantedBy=graphical-session.target
EOF
mkdir -p /etc/systemd/user/graphical-session.target.wants
ln -sfn ../omarchy-mobile-settle.service /etc/systemd/user/graphical-session.target.wants/omarchy-mobile-settle.service
