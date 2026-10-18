# Runs inside Termux (via scripts/termux-run.sh). Updates Termux and installs
# the host-side pieces: X11 server, proot-distro, audio, GPU userspace.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confnew -o Dpkg::Options::=--force-confdef)

apt-get update
apt-get "${APT_OPTS[@]}" full-upgrade
apt-get "${APT_OPTS[@]}" install x11-repo tur-repo
apt-get update
apt-get "${APT_OPTS[@]}" install \
  termux-x11-nightly proot-distro pulseaudio \
  mesa mesa-vulkan-icd-freedreno vulkan-tools virglrenderer-android \
  openssh git curl wget which
# mesa ships Zink, which runs GL on Turnip (Adreno over KGSL). The separate
# mesa-zink package is a frozen 22.x build; make sure it is not the one in use.
apt-get "${APT_OPTS[@]}" purge mesa-zink 2>/dev/null || true

echo "termux-base: done"
