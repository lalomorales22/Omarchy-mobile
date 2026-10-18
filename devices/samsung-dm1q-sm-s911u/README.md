# Samsung Galaxy S23 (SM-S911U, T-Mobile)

See [probe.md](probe.md) for the hardware fingerprint: Snapdragon 8 Gen 2
(SM8550), Adreno 740, 8 GB RAM, Android 16.

![Omarchy desktop (Hyprland) in Termux:X11 on the S23](desktop.png)

## Status

| Tier | Status | Tested |
|---|---|---|
| vm | works: Omarchy desktop, GPU-accelerated (slow, emulated CPU) | 2026-10-18 |
| container | works | 2026-10-18 |
| native | blocked: US Snapdragon bootloader, no OEM unlock | |

## Why native is blocked

US-carrier and US-unlocked Snapdragon Galaxy phones (`SM-S911U`/`U1`) have no
OEM-unlock option. The one known paid workaround needed firmware older than the
April 2023 patch, and Samsung's anti-rollback (bootloader revision 8 on this
unit, `S911USQS8FZI1`) rules out downgrading. The international `SM-S911B` is
the same hardware and can be unlocked; a mainline port for it is in progress at
[dm1q-mainline](https://github.com/MrCamel-Baraa/dm1q-mainline) (boots, Wi-Fi;
no display or GPU driver yet as of 2026-10).

## First boot timeline (8 vCPUs, 4 GB, `-cpu max` with SVE/PAC on)

| Guest uptime | Step |
|---|---|
| ~3 min | systemd up; udev still coldplugging |
| ~3 min | `/boot` times out at systemd's 90 s default → emergency shell (fixed since: `start-vm.sh` raises the timeouts) |
| ~16 min | boot reaches `degraded` (harmless failures: `try-omarchy-locale`, `snapper-cleanup`) |
| ~17–33 min | `omarchy-provision-hardware`: pacman keyring, ~50 deferred hardware steps, initramfs rebuild |
| ~35 min | Omarchy owner setup on tty1 |

## Later boots (`max,sve=off,sme=off,pauth=off`, 8 vCPUs, 4 GB)

| From launch | Icon, shared-uid Termux:X11, all cores (landscape) | Over USB, all cores (portrait) | Icon, regular Termux:X11, cores 0–2 (portrait) |
|---|---|---|---|
| Root shell on hvc1 (systemd up) | 1.8 min | 2.3 min | 4.9 min |
| System `running`, no emergency shell | | ~6 min | |
| SDDM started | 3.8 min | | |
| Hyprland started | 5.0 min | 7.7 min | ~19 min |
| Omarchy bar process up | 5.4 min | | |
| Desktop settled (bar, wallpaper, the settle service's config reload done) | ~10 min | 14 min | not reached at 22 min |

Times from the guest: `ps -eo etimes,comm` for process ages and
`journalctl -b -o short-monotonic` for unit timestamps (the kernel starts
about 30 s after QEMU).

## CPU cores: which Termux:X11 build

Android moves an app's whole process tree between core groups by what is on
screen. QEMU runs inside Termux, so what counts is whether Termux is "on
screen" while Termux:X11 shows Omarchy:

| Termux:X11 build | Launched from | QEMU's cpuset | Cores |
|---|---|---|---|
| regular (`termux-x11-universal-debug.apk`, own uid) | home-screen icon | `/moderate` | 0–2 (Cortex-A510 efficiency cores) |
| regular | `scripts/vm-up.sh` over USB (adbd) | `/` | 0–7 |
| **sharedUid** (`termux-x11-universal-sharedUid-debug.apk`) | home-screen icon | `/top-app` | 0–7 (all, including the Cortex-X3) |

The sharedUid build runs its activity inside the `com.termux` process (same
uid, `android:process="com.termux"`), so Android treats Termux:X11 and Termux
as one app on screen. `install-apps.sh` installs that build; a regular one
already installed has to be uninstalled first (the uid cannot change in place).
With the regular build, bringing Termux itself to the front moved QEMU to
`/top-app`, and it dropped back once Termux:X11 was in front again; a boot to
Hyprland on the efficiency cores took about 19 minutes.

## Device-specific notes

- **Play Protect** rejected the adb install of the Termux debug build
  (`INSTALL_FAILED_VERIFICATION_FAILURE`). `scripts/install-apps.sh` turns off
  `verifier_verify_adb_installs`.
- **GPU:** `glxinfo` under Termux:X11 reports
  `zink Vulkan 1.4 (Turnip Adreno (TM) 740)`, OpenGL 4.6, accelerated.
- **SELinux:** `/dev/kgsl-3d0` opens from the app; `/dev/dri/*` does not.
- **Arch Linux ARM's geo-mirror** stalled mid-install; the container now lists
  Omarchy's ARM mirror first.
- **Home-screen icon:** Termux needs "display over other apps" to start from a
  Termux:Widget shortcut; without it the tap does nothing (logcat:
  `com.termux does not have Display over other apps`). `install-apps.sh` grants it.
- **Android 16 shows an "App Compatibility" warning** for each debuggable
  Termux build (16 KB page alignment). Harmless; "Don't Show Again" dismisses it.
- **Screen sleep:** the Mac's USB port enumerates as an AC charger, so
  `svc power stayon usb` did nothing; `vm-up.sh` uses `stayon true`.
