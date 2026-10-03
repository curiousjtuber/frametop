#!/usr/bin/env bash
# Add the dev box to a Frametop installed by install-host.sh, and what needs it: Remote
# Access (seeing and using the Frametop desktop from another computer, over VNC), whose
# krdp, FreeRDP and TigerVNC come from Fedora in the box. Everything else in the host
# install runs without it (README-host.md).
# Run it on the Frame host, from the install folder (~/.local/share/frametop/app by
# default). Safe to re-run.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"
[ "$FRAME_LOCAL" = 1 ] || { echo "run this on the Frame host, from the install-host.sh folder" >&2; exit 1; }
[ -f "$root/.frametop-host" ] || echo "note: $root isn't an install-host.sh folder; installing from it anyway"

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "1/3 distrobox (container tool, installed in your home folder)"
if [ -x ~/.local/bin/distrobox ]; then
  echo "already installed: $(~/.local/bin/distrobox version | head -1)"
else
  mkdir -p ~/dev/src
  # A tested release, so upstream changes cannot break new installs (as install.sh).
  [ -d ~/dev/src/distrobox ] || git clone --depth 1 --branch 1.8.2.5 https://github.com/89luca89/distrobox.git ~/dev/src/distrobox
  (cd ~/dev/src/distrobox && ./install --prefix ~/.local)
fi

step "2/3 the dev box (Fedora 44 'dev', about 1-2 GB the first time)"
"$root/setup/dev-container.sh"

step "3/3 Remote Access"
"$root/remote/install.sh"
echo "Turn it on in Frametop Remote Access, or with: $root/desktops.sh remote on"
