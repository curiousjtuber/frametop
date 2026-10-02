#!/usr/bin/env bash
# Turn Frametop off on the Steam Frame without deleting anything: the input relay, the 3D
# mouse (pointer service and SteamVR driver), the power service and the gaze service are
# removed, and the launcher's Desktop entry opens the stock desktop again. Settings, the
# settings apps and the builds stay; ./enable.sh turns it back on. Works from a checkout or
# install-cross.sh's install folder, on the Frame, or from a PC over SSH.
#
# Usage: ./disable.sh [--yes]
#   --yes   don't ask; skips the SteamVR restart
#
# SteamVR keeps the driver and the relay's virtual devices until it restarts, so it asks
# first whether to restart SteamVR at the end: once the relay is gone, a terminal in the
# Frametop desktop gets no more keys to answer with.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"

assume_yes=0
for arg in "$@"; do
  case $arg in
    --yes) assume_yes=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

exec 3<&0 </dev/null  # only the question reads the terminal
ask() {  # ask "question" default(y|n)
  [ "$assume_yes" = 1 ] && [ "$2" = y ] && return 0
  [ "$assume_yes" = 1 ] && return 1
  local hint answer
  hint=$([ "$2" = y ] && echo "Y/n" || echo "y/N")
  read -r -p "$1 [$hint] " answer <&3 || answer=
  answer=${answer:-$2}
  [[ $answer =~ ^[Yy] ]]
}

restart=0
ask "Restart SteamVR at the end, so it lets go of the driver and the relay? It closes everything open in VR, including this terminal if it's in a VR desktop." n && restart=1

# enable.sh brings the gaze service back only if it was on.
if on_frame 'systemctl --user is-enabled --quiet frametop-gaze.service 2>/dev/null'; then
  on_frame 'mkdir -p ~/.local/state/frametop && echo gaze > ~/.local/state/frametop/disabled'
else
  on_frame 'mkdir -p ~/.local/state/frametop && : > ~/.local/state/frametop/disabled'
fi

"$root/desktops.sh" uninstall
"$root/desktops.sh" relay uninstall
"$root/pointer/helper/run.sh" uninstall
"$root/power/run.sh" uninstall
"$root/gaze/run.sh" uninstall
"$root/pointer/driver/install.sh" uninstall

echo "Frametop is off. The Frametop desktop, if it's open, stays until you leave it or SteamVR restarts."
if [ "$restart" = 1 ]; then
  on_frame 'systemctl --user restart steamvr.service'
else
  echo "Restart SteamVR (or the headset) when it suits you: systemctl --user restart steamvr.service"
fi
