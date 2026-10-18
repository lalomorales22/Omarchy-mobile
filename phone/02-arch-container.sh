# Runs inside Termux. Creates the "omarchy" proot container from the official
# Arch Linux ARM aarch64 rootfs (signature-verified), then initialises pacman.
set -euo pipefail

NAME=omarchy
URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
# Arch Linux ARM Build System <builder@archlinuxarm.org>
ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6
DL="$PREFIX/tmp/alarm"

if [ -d "$PREFIX/var/lib/proot-distro/containers/$NAME" ]; then
  echo "container '$NAME' already exists; skipping install"
else
  apt-get install -y gnupg
  mkdir -p "$DL" && cd "$DL"
  curl -fL --retry 3 -o rootfs.tar.gz "$URL"
  curl -fL --retry 3 -o rootfs.tar.gz.sig "$URL.sig"
  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$ALARM_KEY"
  gpg --batch --status-fd 1 --verify rootfs.tar.gz.sig rootfs.tar.gz | grep -q "VALIDSIG $ALARM_KEY" \
    || { echo "rootfs signature check FAILED" >&2; exit 1; }
  echo "rootfs signature OK ($ALARM_KEY)"
  proot-distro install -n "$NAME" "$DL/rootfs.tar.gz"
  rm -rf "$DL"
fi

proot-distro login "$NAME" -- /bin/bash -euo pipefail -c '
  # pacman 7 drops to the "alpm" user and uses Landlock; neither works under proot.
  grep -q "^DisableSandbox" /etc/pacman.conf || sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
  sed -i "s/^DownloadUser/#DownloadUser/" /etc/pacman.conf
  # Omarchy'"'"'s own ARM mirror first (what Omarchy on aarch64 uses); ALARM'"'"'s geo-mirror stalls.
  grep -q arm-mirror.omarchy.org /etc/pacman.d/mirrorlist ||
    sed -i "1i Server = https://arm-mirror.omarchy.org/\$arch/\$repo" /etc/pacman.d/mirrorlist
  # The tarball ships placeholder users and the default ALARM kernel; neither is wanted here.
  userdel -r alarm 2>/dev/null || true
  pacman-key --init
  pacman-key --populate archlinuxarm
  # Drop the kernel before upgrading so pacman does not rebuild an initramfs nobody boots.
  pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
  pacman -Syu --noconfirm
  pacman -S --noconfirm --needed base-devel git sudo
'
echo "arch-container: done"
