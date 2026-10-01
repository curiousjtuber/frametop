#!/usr/bin/env bash
# Turn Frametop back on after ./disable.sh: the input relay, the 3D mouse (SteamVR driver
# and pointer service), the power service, the gaze service if it was on, and the
# launcher's Desktop entry.
# It builds nothing: it installs the programs BINARIES in ~/.config/frametop.conf picks
# (dev: build/, cross: build-cross/), and stops if they aren't there; ./install.sh builds
# them. Works on the Frame or from a PC over SSH.
#
# Usage: ./enable.sh [--yes] [--gaze]
#   --yes    don't ask; skips the SteamVR restart
#   --gaze   also turn on the gaze service, even if it wasn't on before
#
# SteamVR loads the driver, and finds the relay's devices, only when it starts, so it
# asks whether to restart SteamVR at the end.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"

assume_yes=0 gaze=0
for arg in "$@"; do
  case $arg in
    --yes) assume_yes=1 ;;
    --gaze) gaze=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
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

out=build
[ "$(frame_binaries)" = cross ] && out=build-cross
for f in screens/$out/ft-screens pointer/helper/$out/ft-pointer pointer/driver/$out/driver_ft_pointer.so \
  power/$out/ft-powerd; do
  on_frame "test -e $f" || { echo "$f is missing: run ./install.sh$([ $out = build-cross ] && echo ' --cross') to build and install" >&2; exit 1; }
done
on_frame 'grep -qx gaze ~/.local/state/frametop/disabled 2>/dev/null' && gaze=1

restart=0
ask "Restart SteamVR at the end, to load the driver and start the relay before it? It closes everything open in VR, including this terminal if it's in a VR desktop." n && restart=1

"$root/desktops.sh" relay install
"$root/pointer/driver/install.sh" install 2>&1 | grep -v xdg-open
"$root/pointer/helper/run.sh" install
"$root/power/run.sh" install
[ "$gaze" = 1 ] && "$root/gaze/run.sh" install
"$root/desktops.sh" install >/dev/null
on_frame 'rm -f ~/.local/state/frametop/disabled'

echo "Frametop is on ($out/): the launcher's Desktop entry opens the multi-screen desktop."
if [ "$restart" = 1 ]; then
  on_frame 'systemctl --user restart steamvr.service'
else
  echo "The relay and the driver start with SteamVR's next start: systemctl --user restart steamvr.service"
fi
