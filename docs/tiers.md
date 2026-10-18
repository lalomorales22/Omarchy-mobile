# Tiers

Every phone lands in one or more tiers. `scripts/probe.sh` reports which ones a
phone can reach; each `devices/<id>/README.md` records which ones were tested.

## vm: real Omarchy in QEMU, on stock Android

Termux runs `qemu-system-aarch64` and boots the stock generic-aarch64 Omarchy
disk that [omacom/try-omarchy](https://github.com/omacom/try-omarchy) publishes
for Apple Silicon Macs (`phone/10-vm-image.sh`, `phone/start-vm.sh`). The VM has
its own kernel and a virtio GPU, so Hyprland gets the DRM device it needs and
Omarchy installs, updates and themes itself exactly as it does on a laptop.
Termux:X11 shows the VM's screen.

- **Needs:** any arm64 Android 7+ phone; no unlock, no root, nothing wiped.
- **GPU:** guest OpenGL goes through virgl to the phone's GPU (Zink on Turnip
  for Adreno). Other GPUs fall back to `OMARCHY_VM_GL=llvmpipe`.
- **Cost:** no KVM on stock Android, so the CPU is emulated (TCG). Expect a
  slow first boot and a usable but not snappy desktop.

## container: Arch Linux ARM in proot

Termux runs a proot container from the official Arch Linux ARM rootfs
(`phone/02-arch-container.sh`). The CPU runs at full native speed. Hyprland
itself can't start here, because Android's SELinux policy keeps apps away from
`/dev/dri`, and Hyprland's backend (aquamarine) allocates every buffer through
GBM on a DRM node. The container is the fast lane for CLI tools and builds.

## native: Omarchy as the phone's only OS

Unlock the bootloader, boot a mainline Linux kernel, install Arch Linux ARM and
Omarchy on the phone's storage. Full speed, real GPU, no Android.

- **Needs:** an unlockable bootloader *and* a mainline kernel port for the SoC
  (display, touch, GPU at minimum). Check [postmarketOS](https://wiki.postmarketos.org/wiki/Devices)
  for the device first.
- **Blocked on:** US-carrier Samsung Snapdragon phones (no OEM unlock at all),
  and any phone nobody has ported mainline Linux to yet.
