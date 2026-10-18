# Runs inside Termux. Boots the Omarchy VM in QEMU and shows it through
# Termux:X11. Mirrors try-omarchy's virtual hardware (macos/run-qemu-gpu.sh),
# minus its Mac-only bridges, with TCG in place of Apple's hypervisor.
#
#   start-vm.sh [portrait|landscape]  screen orientation; the last choice is
#                                     remembered (OMARCHY_VM_ORIENTATION also works)
#   OMARCHY_VM_GL=zink|llvmpipe|off   guest GPU: virgl on Adreno (default),
#                                     virgl on the host CPU, or 2D only
#   OMARCHY_VM_RAM=4G  OMARCHY_VM_CPUS=<all cores>
#   OMARCHY_VM_CPU=max,sve=off,sme=off,pauth=off
#                                    TCG emulates SVE/SME and pointer auth
#                                    slowly; glibc picks SVE string routines
#                                    and Arch ARM builds PAC into every function
#   OMARCHY_VM_SIZE=WxH              guest screen; defaults to the X screen
#                                    (Termux:X11 at 150% scale)
#   OMARCHY_VM_DEBUG=1               root shell on hvc1 (scripts/vm-shell.sh)
#
# Any of these can also live in ~/omarchy-vm/config (KEY=value lines), which is
# how settings reach a launch from the home-screen icon.
set -euo pipefail

VM="$HOME/omarchy-vm"
if [ -f "$VM/config" ]; then
  set -a
  . "$VM/config"
  set +a
fi
CODE="$PREFIX/share/qemu/edk2-aarch64-code.fd"
RAM=${OMARCHY_VM_RAM:-4G}
CPUS=${OMARCHY_VM_CPUS:-$(nproc)}
CPU=${OMARCHY_VM_CPU:-max,sve=off,sme=off,pauth=off}
GL=${OMARCHY_VM_GL:-zink}
ORIENTATION=${1:-${OMARCHY_VM_ORIENTATION:-$(cat "$VM/orientation" 2>/dev/null || echo landscape)}}
case $ORIENTATION in
  portrait|landscape) echo "$ORIENTATION" >"$VM/orientation" ;;
  *) echo "orientation must be portrait or landscape" >&2; exit 1 ;;
esac

[ -f "$VM/omarchy.img" ] || { echo "no disk; run phone/10-vm-image.sh first" >&2; exit 1; }
# The ESP edit below must never touch a disk a running guest has mounted.
if pgrep -f "qemu-system-aarch64.*$VM/omarchy.img" >/dev/null; then
  echo "the Omarchy VM is already running" >&2
  exit 1
fi

# Kernel command line additions, written into the ESP's limine.conf before each
# boot (Omarchy regenerates that file on kernel updates). Under TCG, udev takes
# minutes to create /dev/disk/by-uuid links; with systemd's 90 s defaults /boot
# times out and boot drops to the emergency shell.
flags="systemd.default_device_timeout_sec=600 systemd.default_timeout_start_sec=300"
[ "${OMARCHY_VM_DEBUG:-0}" = 1 ] && flags+=" systemd.debug_shell=/dev/hvc1"

# The rest of the guest's adjustments live in guest-setup.sh (uwsm's 30 s
# limits, Hyprland config reload retries): the first autologin needs them
# before anyone could log in to fix things. The launcher copies the script to
# the boot partition, and a unit passed as a systemd credential
# (systemd.extra-unit.*) runs it before sysinit.target. Only the unit rides on
# the command line, which arm64 caps at 2048 bytes.
setup_unit='[Unit]
Description=Omarchy Mobile guest settings
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target
ConditionPathExists=/boot/omarchy-mobile/guest-setup.sh
[Service]
Type=oneshot
ExecStart=/bin/sh /boot/omarchy-mobile/guest-setup.sh'
flags+=" systemd.set_credential_binary=systemd.extra-unit.omarchy-mobile.service:$(printf '%s\n' "$setup_unit" | base64 -w0)"
flags+=" systemd.wants=omarchy-mobile.service"

[ -f "$VM/guest-setup.sh" ] || { echo "no guest-setup.sh; run scripts/install-launcher.sh" >&2; exit 1; }
esp_start=$(sfdisk -d "$VM/omarchy.img" | awk -F'[=,]' '/omarchy.img1 :/{gsub(/ /,"",$2); print $2}')
esp="$VM/omarchy.img@@$((esp_start * 512))"
export MTOOLS_SKIP_CHECK=1
mmd -i "$esp" ::/omarchy-mobile 2>/dev/null || true
mtype -i "$esp" ::/omarchy-mobile/guest-setup.sh 2>/dev/null | cmp -s - "$VM/guest-setup.sh" ||
  mcopy -o -i "$esp" "$VM/guest-setup.sh" ::/omarchy-mobile/guest-setup.sh
mtype -i "$esp" ::/limine.conf >"$VM/limine.conf.cur"
cp "$VM/limine.conf.cur" "$VM/limine.conf.work"

# From its first boot on, Omarchy boots a UKI (kernel, initramfs and command
# line in one EFI binary) and writes the entry without a cmdline:. Give the
# entry one, copied from the UKI: with Secure Boot off (QEMU's firmware),
# systemd-stub takes the loader's command line over the embedded one.
if ! grep -q '^ *cmdline:' "$VM/limine.conf.work"; then
  uki=$(sed -n 's|^ *path: boot():\(/EFI/Linux/[^ ]*\.efi\).*|\1|p' "$VM/limine.conf.work" | head -1)
  if [ -n "$uki" ]; then
    mcopy -o -i "$esp" "::$uki" "$VM/uki.efi"
    embedded=$(grep -a -o -m1 'root=[[:print:]]*' "$VM/uki.efi" | head -1 | sed 's/ *$//')
    rm -f "$VM/uki.efi"
    [ -n "$embedded" ] && sed -i "s|^\( *\)path: boot():$uki.*|&\n\1cmdline: $embedded|" "$VM/limine.conf.work"
  fi
fi

sed -E -e 's/ [^ ]*omarchy-mobile[^ ]*//g' \
  -e 's/ (systemd\.default_device_timeout_sec|systemd\.default_timeout_start_sec|systemd\.debug_shell)=[^ ]*//g' \
  -e "/^ *cmdline: /s|\$| $flags|" "$VM/limine.conf.work" >"$VM/limine.conf.new"
rm -f "$VM/limine.conf.work"
cmp -s "$VM/limine.conf.cur" "$VM/limine.conf.new" || mcopy -o -i "$esp" "$VM/limine.conf.new" ::/limine.conf

export DISPLAY=:0
# Ask the display itself: the server's process name varies with how it started.
if ! xrandr >/dev/null 2>&1; then
  termux-x11 :0 -ac >"$VM/x11.log" 2>&1 &
  for _ in $(seq 1 20); do xrandr >/dev/null 2>&1 && break; sleep 0.5; done
fi

# Openbox keeps QEMU's window fullscreen, and resizes it when the X screen
# turns; QEMU then hands the guest its new screen size.
cat >"$VM/openbox-rc.xml" <<'XML'
<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications><application class="*"><decor>no</decor><fullscreen>yes</fullscreen></application></applications>
</openbox_config>
XML
if pgrep -x openbox >/dev/null; then
  openbox --reconfigure
else
  openbox --config-file "$VM/openbox-rc.xml" >"$VM/openbox.log" 2>&1 &
fi

# The key bar's ROTATE button sends CTRL+SHIFT+F12. QEMU grabs the keyboard
# while its window has focus, so a window-manager binding never fires;
# omarchy-rotate-keys (phone/rotate-keys.c) reads XInput2 raw key events,
# which arrive regardless, and runs omarchy-rotate.
if ! pgrep -f '^omarchy-rotate-keys$' >/dev/null; then
  omarchy-rotate-keys >"$VM/rotate-keys.log" 2>&1 &
fi

# Termux:X11 settings: orientation, fullscreen at 150% (readable on a phone,
# fewer pixels for the emulated CPU), tap-to-click, the soft keyboard drawn
# over the screen rather than resizing it (a resize would make Hyprland
# re-mode), and a key bar with SUPER, which Android keyboards lack. Fed as
# key=value lines: the argument form splits on ':', which the key bar needs.
termux-x11-preference >/dev/null 2>&1 <<EOF || echo "warning: Termux:X11 did not take its settings; is the app open?" >&2
forceOrientation=$ORIENTATION
fullscreen=true
hideCutout=true
displayResolutionMode=scaled
displayScale=150
touchMode=Simulated touchscreen
Reseed=false
extra_keys_config=[[{macro: 'CTRL SHIFT F12', display: 'ROTATE'},'ESC','TAB','CTRL','ALT','SHIFT','UP','KEYBOARD'],[{key: 'META', display: 'SUPER'},'F1','ENTER','SPACE','BKSP','LEFT','DOWN','RIGHT']]
EOF

# The X screen follows the app once it has rotated; the guest takes its size.
x_size() { xrandr 2>/dev/null | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1 \2/p'; }
for _ in $(seq 1 20); do
  read -r w h < <(x_size) || true
  case $ORIENTATION in
    portrait) [ "${h:-0}" -gt "${w:-0}" ] && break ;;
    landscape) [ "${w:-0}" -gt "${h:-0}" ] && break ;;
  esac
  sleep 0.5
done
SIZE=${OMARCHY_VM_SIZE:-${w:-1560}x${h:-720}}
echo "guest screen $SIZE ($ORIENTATION), gpu $GL, $CPUS cpus, $RAM"

case $GL in
  zink) export MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform
        gpu=virtio-gpu-gl-pci display=sdl,gl=on ;;
  llvmpipe) export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
        gpu=virtio-gpu-gl-pci display=sdl,gl=on ;;
  off) gpu=virtio-gpu-pci display=sdl ;;
  *) echo "OMARCHY_VM_GL must be zink, llvmpipe or off" >&2; exit 1 ;;
esac

exec qemu-system-aarch64 \
  -name Omarchy \
  -machine virt,gic-version=3 \
  -accel tcg,thread=multi,tb-size=1024 \
  -cpu "$CPU" \
  -smp "$CPUS" -m "$RAM" \
  -nodefaults \
  -drive "if=pflash,format=raw,readonly=on,file=$CODE" \
  -drive "if=pflash,format=raw,file=$VM/efivars.fd" \
  -drive "if=none,id=root,file=$VM/omarchy.img,format=raw,cache=writeback,discard=unmap" \
  -device virtio-blk-pci,drive=root,bootindex=0 \
  -netdev user,id=net,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=net,romfile= \
  -device "$gpu,max_outputs=1,xres=${SIZE%x*},yres=${SIZE#*x},romfile=" \
  -display "$display,show-cursor=on" \
  -device virtio-keyboard-pci,romfile= \
  -device virtio-tablet-pci,romfile= \
  -object rng-random,id=rng,filename=/dev/urandom \
  -device virtio-rng-pci,rng=rng \
  -device virtio-serial-pci,id=serial \
  -chardev "file,id=hvc0,path=$VM/console.log" \
  -device virtconsole,bus=serial.0,nr=0,chardev=hvc0 \
  -chardev "socket,id=hvc1,path=$VM/shell.sock,server=on,wait=off" \
  -device virtconsole,bus=serial.0,nr=1,chardev=hvc1 \
  -serial "file:$VM/uefi.log" \
  -monitor "unix:$VM/monitor.sock,server,nowait"
