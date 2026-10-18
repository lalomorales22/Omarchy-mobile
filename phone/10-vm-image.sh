# Runs inside Termux. Installs QEMU and fetches the stock generic-aarch64 Omarchy
# disk that omacom/try-omarchy publishes, verified against pinned SHA-256s.
# To bump: take the new tag's asset digests from
#   https://api.github.com/repos/omacom/try-omarchy/releases/latest
set -euo pipefail

TAG=v1.0.1
BASE="https://github.com/omacom/try-omarchy/releases/download/$TAG"
PARTS=(
  "omarchy-aarch64-edge.img.zst.001 c637c85e4b89b2d2d9c00d6a11ffb7122c6f5b2f6631970238bef38d6c540460"
  "omarchy-aarch64-edge.img.zst.002 b7eb4d571497111639107e616389e2e14e5c4535e9a57d4076718f36aecd89f8"
  "omarchy-aarch64-edge.img.zst.003 72cb07932f891e90836fb69395eec07240449e1dd3b9708f596b789fbd1171c8"
)
VM="$HOME/omarchy-vm"
DISK="$VM/omarchy.img"

# mtools + fdisk let start-vm.sh edit the guest's FAT boot partition offline.
apt-get install -y qemu-system-aarch64 qemu-utils zstd mtools fdisk socat openbox xorg-xrandr

mkdir -p "$VM/download"
cd "$VM/download"

if [ -f "$DISK" ]; then
  echo "disk already exists at $DISK; delete it to re-download"
else
  for entry in "${PARTS[@]}"; do
    set -- $entry
    name=$1 sum=$2
    if ! echo "$sum  $name" | sha256sum -c --status 2>/dev/null; then
      curl -fL --retry 5 -C - -o "$name" "$BASE/$name"
    fi
    echo "$sum  $name" | sha256sum -c
  done
  cat omarchy-aarch64-edge.img.zst.0* | zstd -d --sparse -o "$DISK.partial"
  mv "$DISK.partial" "$DISK"
  rm -f omarchy-aarch64-edge.img.zst.0*
fi

# A writable UEFI variable store per VM, next to the disk.
CODE=$(ls "$PREFIX"/share/qemu/edk2-aarch64-code.fd)
[ -f "$VM/efivars.fd" ] || truncate -s "$(stat -c %s "$CODE")" "$VM/efivars.fd"

ls -lhs "$VM"
echo "vm-image: done"
