#!/usr/bin/env bash
# Install the hand recorder on a Frame that has Frametop (get.sh --experimental): the settings
# apps' Python environment, which the window runs on (setup/pyside-venv.sh), hand tracking's
# camera broker, tracker and Python (hands/build.sh: the first build fetches and builds ncnn, a
# few minutes, and downloads about 165 MB of Python packages), the headset panel
# (hands/rec/build.sh), ft-camd's capabilities (hands/run.sh caps: asks for the password, once
# per build), and "Frametop Hand Recorder" in the app menu (for Frametop's desktop: it isn't
# tested from SteamVR's "Launch a program", which runs apps outside it; the standalone recorder
# is for that). Everything builds and runs on the host; the dev container isn't needed.
# It doesn't turn on Frametop's live hand tracking (that's hands/run.sh install, still deferred).
# Usage: hands/rec/install.sh            install or update
#        hands/rec/install.sh uninstall  remove the menu entry (recordings stay where they are)
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
. "$root/scripts/_env.sh"
entry='~/.local/share/applications/frametop-handrec.desktop'

case ${1:-install} in
  install)
    echo "== 1/4 the window's Python environment (PySide6 on the host's Qt)"
    "$root/setup/pyside-venv.sh"
    echo "== 2/4 hand tracking: ft-camd, ft-hands, and their Python"
    "$root/hands/build.sh"
    echo "== 3/4 the headset panel: ft-handpanel"
    "$root/hands/rec/build.sh"
    echo "== 4/4 ft-camd's capabilities (asks for your password) and the menu entry"
    "$root/hands/run.sh" caps
    "$root/scripts/conf-migrate.sh"   # HANDS_SWAP_SIDES=0, the old default, becomes auto
    fill_template "$root/hands/rec/ft-handrec.desktop" |
      on_frame "chmod +x hands/rec/ft-handrec && mkdir -p ~/.local/share/applications && cat > $entry"
    echo
    echo "Installed. On Frametop's desktop, open \"Frametop Hand Recorder\" from the app menu."
    echo "Recordings go to ~/.local/share/frametop/hands/contrib."
    ;;
  uninstall)
    on_frame "rm -f $entry"
    echo "Removed the menu entry. Your recordings are still in ~/.local/share/frametop/hands/contrib:"
    echo "delete that folder to remove them."
    ;;
  *) echo "usage: $0 [install|uninstall]" >&2; exit 2 ;;
esac
