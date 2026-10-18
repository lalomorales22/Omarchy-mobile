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

# Hyprland only removes the error banner after a reload that succeeds, and a
# startup reload can leave one behind even when `hyprctl configerrors` is
# already empty. Reload once the session has settled, then keep retrying while
# a reload still times out (a future Hyprland the patch above doesn't match).
conf /usr/local/bin/omarchy-mobile-settle <<'EOF'
#!/bin/sh
sleep 180
hyprctl reload >/dev/null 2>&1 || true
for _ in $(seq 1 10); do
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

# Rotation: when the phone turns, QEMU gives the virtual monitor a new preferred
# mode, but Hyprland keeps the mode list it read at startup, so "preferred"
# still means the old shape and the picture is stretched. Follow the kernel's
# preferred mode instead, and re-apply it after every config reload.
conf /usr/local/bin/omarchy-mobile-screen <<'EOF'
#!/usr/bin/python3 -I
import glob
import os
import socket
import subprocess


def screens():
    found = []
    for connector in glob.glob("/sys/class/drm/card*-Virtual-*"):
        try:
            with open(connector + "/status") as f:
                if f.read().strip() != "connected":
                    continue
            with open(connector + "/modes") as f:
                mode = f.readline().strip()
        except OSError:
            continue
        if mode:
            found.append((os.path.basename(connector).split("-", 1)[1], mode))
    return found


def apply(current):
    for output, mode in current:
        lua = f'hl.monitor({{ output = "{output}", mode = "{mode}", position = "0x0", scale = "auto" }})'
        subprocess.run(["hyprctl", "eval", lua], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


events = socket.socket(socket.AF_UNIX)
events.connect(f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket2.sock")
events.settimeout(1)
last = screens()
apply(last)
pending = b""
while True:
    try:
        data = events.recv(4096)
        if not data:
            break
        pending += data
        *lines, pending = pending.split(b"\n")
        if any(line.startswith((b"configreloaded>>", b"monitoradded")) for line in lines):
            apply(screens())
    except socket.timeout:
        pass
    now = screens()
    if now != last:
        last = now
        apply(now)
EOF
chmod 755 /usr/local/bin/omarchy-mobile-screen
conf /etc/systemd/user/omarchy-mobile-screen.service <<'EOF'
[Unit]
Description=Omarchy Mobile: follow the phone's screen orientation
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/local/bin/omarchy-mobile-screen
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
ln -sfn ../omarchy-mobile-screen.service /etc/systemd/user/graphical-session.target.wants/omarchy-mobile-screen.service
