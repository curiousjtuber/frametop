#!/usr/bin/env bash
# Create or update the "dev" container on the Steam Frame (Fedora 44 toolbox, aarch64, via
# distrobox). Only Remote Access needs it now (session/remote-desktop.sh, vnc-bridge.sh:
# Fedora's krdp, FreeRDP and TigerVNC); Frametop's own programs build and run on the host,
# and its Python apps in a Flatpak (pack/host-and-flatpak.md), so install.sh no longer runs
# this. Safe to re-run: it only creates what's missing and dnf skips installed packages. Its
# packages and base image are the build image's (setup/packages.txt, pack/Containerfile); an
# existing container keeps its own base.
# Usage: setup/dev-container.sh   (on the Frame, or from a PC over SSH)
# Needs distrobox in ~/.local/bin on the Frame (see the top-level README).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$root/scripts/_env.sh"

# The packages: setup/packages.txt's "both" and "dev" lines (the release image installs its
# "both" and "image" ones). The image: pack/Containerfile's base, by its digest.
read -ra packages <<<"$(sed -nE 's/#.*//; s/^(both|dev):(.*)/\2/p' "$root/setup/packages.txt" | tr '\n' ' ')"
image=$(sed -nE 's/^FROM ([^ ]+@sha256:[0-9a-f]{64}) AS runtime-common$/\1/p' "$root/pack/Containerfile")
[ -n "$image" ] || { echo "no digest-pinned base image in pack/Containerfile" >&2; exit 1; }

on_frame_script "$FRAME_REPO" "$image" "${packages[@]}" <<'EOF'
set -euo pipefail
repo=$1 image=$2
shift 2
distrobox=$HOME/.local/bin/distrobox
[ -x "$distrobox" ] || { echo "distrobox not found at $distrobox (see the top-level README)" >&2; exit 1; }
if ! podman container exists dev; then
  echo "creating the dev container ($image)"
  "$distrobox" create --yes --name dev --image "$image"
fi
"$repo/scripts/container-up.sh" dev  # in a scope of its own, not this shell's
"$distrobox" enter dev -- bash -c '
set -euo pipefail
repo=$1
shift
echo "installing ${#@} packages (already-installed ones are skipped)"
sudo -n dnf install -y -q "$@" 2>&1 | { grep -vE "is already installed|^Nothing to do|^$" || true; }
# OpenVR programs built here (the pointer helper and probe) look for the runtime at /opt/steamvr.
[ -e /opt/steamvr ] || sudo -n ln -s /run/host/opt/steamvr /opt/steamvr
# Two Fedora packages break Remote Access as they update; hold them (see the script).
"$repo/setup/container-pins.sh"
echo "dev container ready: $(. /etc/os-release; echo $PRETTY_NAME), glibc $(ldd --version | head -1 | grep -oE "[0-9.]+$")"
' dev "$repo" "$@"
EOF
