# Debugging the VM

The guest boots on an emulated CPU, so everything takes minutes and a black
screen is normal for a while. These tools show what it is doing.

## QEMU monitor

```sh
scripts/vm-monitor.sh 'info status'            # running / paused
scripts/vm-monitor.sh 'info blockstats'        # disk reads climbing = still booting
scripts/vm-monitor.sh screenshot out.png       # the guest's screen, on the host
scripts/vm-monitor.sh system_powerdown         # ACPI power button: clean shutdown
```

`screenshot` reads the virtio-gpu scanout. "Display output is not active" means
the guest has not set a mode yet.

## Logs on the phone

In `~/omarchy-vm/` inside Termux:

| File | Contents |
|---|---|
| `uefi.log` | Firmware output (the PL011 serial port) |
| `console.log` | Guest kernel/systemd console on `hvc0` (quiet by default) |
| `x11.log`, `openbox.log` | Display side |

## Root shell in the guest

Boot with `OMARCHY_VM_DEBUG=1` (for example `OMARCHY_VM_DEBUG=1 scripts/vm-up.sh`).
The launcher adds `systemd.debug_shell=/dev/hvc1` to the guest kernel command
line, and `hvc1` is a socket in Termux's private storage:

```sh
scripts/vm-shell.sh 'systemctl --failed'
WAIT=120 scripts/vm-shell.sh 'journalctl -b -p err --no-pager'
```

It is a passwordless root shell, which is why it is off by default. Anything
running as the Termux app can reach the socket.

## Known first-boot behaviour

- **Emergency shell, "root account is locked".** udev needs minutes under TCG,
  so `/dev/disk/by-uuid/*` appears after systemd's 90 s device timeout and
  `/boot` fails to mount. `phone/start-vm.sh` now raises the timeouts on the
  guest kernel command line. If you still land there, press Enter: systemd
  retries the target, and the mounts succeed once udev has caught up.
- **Long wait before the setup screen.** Omarchy's
  `omarchy-provision-hardware.service` creates the machine's pacman keyring and
  runs about 50 deferred hardware scripts before the owner setup starts on
  tty1. Finished steps are dropped from
  `/var/lib/omarchy/image/deferred-steps`, so the work survives a reboot.
- **`try-omarchy-locale.service` failed.** It reads the Mac app's language
  setting. Harmless.
- **Black screen with a cursor after setup.** Hyprland needs about a minute to
  start and another to export `WAYLAND_DISPLAY`. uwsm allows 30 s for each
  (`wayland-wm@.service`'s `TimeoutStartSec`, `wayland-session-waitenv.service`'s
  `TimeoutStartSec`, and waitenv's own `UWSM_WAIT_VARNAMES_TIMEOUT` countdown),
  then shuts the session down. SDDM's greeter is a Hyprland too, and SDDM kills
  it after 15 s without a Wayland socket, so it loops. `phone/start-vm.sh`
  copies `phone/guest-setup.sh` to the guest's boot partition and passes a
  unit (as a systemd credential on the kernel command line) that runs it,
  raising all three to 10 minutes before the first autologin. Check with
  `scripts/vm-shell.sh 'systemctl status omarchy-mobile'`.
- **Red "Your config has errors … [Lua] execution timed out in config reload"
  banner.** Hyprland stops any Lua config (re)load after 1.5 s
  (`LUA_TIMEOUT_CONFIG_RELOAD_MS` in Hyprland's `ConfigManager.hpp`, not
  configurable), and evaluating Omarchy's config can take longer under TCG.
  The rest of that file's config is skipped. `omarchy-mobile-settle.service`
  (installed by `guest-setup.sh`) reloads every minute until a reload fits.
  Note that `hyprctl` prints nothing when Hyprland's socket is too slow to
  answer, so test with `hyprctl -j configerrors` and its exit code.

- **Limine: "PANIC: linux: failed to open kernel".** The ESP's `limine.conf`
  points at a kernel that is gone. The factory image boots
  `/<machine-id>/linux-omarchy/vmlinuz`. From the first boot on, Omarchy boots
  a UKI (`/EFI/Linux/omarchy_linux-omarchy.efi`) and rewrites `limine.conf`, so
  never put back a copy saved before the first boot. A working UKI entry is
  `protocol: efi` plus `path: boot():/EFI/Linux/omarchy_linux-omarchy.efi`;
  `start-vm.sh` adds the `cmdline:` itself.

## Checking Hyprland from the debug shell

```sh
scripts/vm-shell.sh 'sig=$(ls -t /run/user/1000/hypr | head -1); \
  runuser -u <user> -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl monitors'
scripts/vm-shell.sh 'grep Renderer: /run/user/1000/hypr/*/hyprland.log'
```

On the S23 the renderer line reads
`virgl (zink Vulkan 1.4(Turnip Adreno (TM) 740 (MESA_TURNIP)))`: guest OpenGL
through virgl to the phone's GPU.
