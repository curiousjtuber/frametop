#!/usr/bin/env bash
# Install everything on the Steam Frame: Frametop (multi-screen desktop, input relay,
# universal 3D mouse, settings apps), built with the SteamOS host's own gcc and run on the
# host, and optionally gaze mode, our own eye tracker for it, Remote Access (which needs the
# dev box, a Fedora container) and the Bluetooth fixes. Run it on the headset in a terminal,
# from this repo. It copies the repo into an install folder and installs from there, so
# Frametop doesn't run from this checkout. It's safe to re-run, for example after `git
# pull`. (Hand tracking, hands/, is deferred: it isn't offered here.) (It also works from a
# PC over SSH; see "Developing from a PC" in the README.)
#
# Usage: ./install.sh [--prefix DIR] [--yes] [--no-dev-box] [--no-bluetooth]
#   --prefix DIR    the install folder (default ~/.local/share/frametop/app; . installs in
#                   this checkout). From a PC, the Frame's synced copy (~/dev/frametop by
#                   default) is the install folder, and this moves it.
#   --yes           don't ask; installs gaze mode, our eye tracker if sudo can run without a
#                   password prompt, and the dev box; skips the Bluetooth fixes and the
#                   SteamVR restart
#   --no-dev-box    don't set up the dev box (no Remote Access)
#   --no-bluetooth  don't offer the Bluetooth fixes
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"

args=("$@") assume_yes=0 bluetooth=1 dev_box=1 prefix=
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) prefix=${2:?--prefix needs a folder}; shift ;;
    --prefix=*) prefix=${1#--prefix=} ;;
    --yes) assume_yes=1 ;;
    --no-dev-box) dev_box=0 ;;
    --no-bluetooth) bluetooth=0 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$FRAME_LOCAL" = 0 ]; then
  [ -z "$prefix" ] || export FRAME_REPO=$prefix  # the scripts below sync and install there
else
  prefix=$(realpath -m "${prefix:-$HOME/.local/share/frametop/app}")
  if [ "$prefix" != "$(realpath "$root")" ]; then
    # Install from a copy, so Frametop doesn't run from (or break with) this checkout. It's
    # replaced on every run, so it must be ours: missing, empty, or made by an earlier run.
    case $prefix/ in "$(realpath "$root")"/*) echo "the install folder can't be in this checkout" >&2; exit 2 ;; esac
    case $(realpath "$root")/ in "$prefix"/*) echo "the install folder can't hold this checkout" >&2; exit 2 ;; esac
    [ ! -e "$prefix" ] || [ -z "$(ls -A "$prefix")" ] || [ -f "$prefix/.frametop-install" ] ||
      { echo "$prefix isn't empty and isn't a Frametop install folder: choose another with --prefix" >&2; exit 1; }
    mkdir -p "$prefix"
    # As scripts/sync.sh copies to the Frame: what's gitignored stays out, and the copy's
    # own builds (build/) stay in it.
    rsync -a --delete --filter=':- .gitignore' --exclude=.git --exclude=build/ --exclude=.env --exclude='.env.*' \
      "$root/" "$prefix/"
    echo "Copied from $root by install.sh, and replaced on every run: keep nothing of yours here." \
      > "$prefix/.frametop-install"
    git -C "$root" log -1 --format='%h (%cd)' --date=short > "$prefix/VERSION" 2>/dev/null || rm -f "$prefix/VERSION"
    echo "copied $root to $prefix; installing from there"
    exec "$prefix/install.sh" "${args[@]}"
  fi
fi

# Only the questions read from the terminal (or whatever stdin is); the build steps get
# no input, so they can't swallow typed-ahead or piped answers.
exec 3<&0 </dev/null

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ask() {  # ask "question" default(y|n)
  [ "$assume_yes" = 1 ] && [ "$2" = y ] && return 0
  [ "$assume_yes" = 1 ] && return 1
  local hint answer
  hint=$([ "$2" = y ] && echo "Y/n" || echo "y/N")
  read -r -p "$1 [$hint] " answer <&3 || answer=
  answer=${answer:-$2}
  [[ $answer =~ ^[Yy] ]]
}
# Can sudo run here without a password prompt (SUDO_ASKPASS, the repo's .env, a recent sudo)?
# See frame_sudo in scripts/_env.sh.
sudo_quiet() {
  { [ "$FRAME_LOCAL" = 1 ] && [ -n "${SUDO_ASKPASS:-}" ]; } && return 0
  grep -q '^steamos_root_pwd=.' "$REPO_ROOT/.env" 2>/dev/null && return 0
  on_frame 'sudo -n true' 2>/dev/null
}

if [ "$FRAME_LOCAL" = 1 ]; then
  echo "Installing on this Steam Frame from $FRAME_REPO"
else
  echo "Installing on $FRAME_HOST over SSH (repo copy at $FRAME_REPO)"
  "$root/scripts/sync.sh" >/dev/null
  # The synced copy is the install folder: mark it as one, so install.sh run on the Frame
  # itself (from a checkout there) replaces it instead of refusing it.
  on_frame "echo 'Synced from a PC by install.sh, and replaced on every sync: keep nothing of yours here.' > .frametop-install"
  # Which commit is installed, as the on-Frame copy above records it (sync.sh keeps it).
  if version=$(git -C "$root" log -1 --format='%h (%cd)' --date=short 2>/dev/null); then
    on_frame "echo '$version' > VERSION"
  else
    on_frame "rm -f VERSION"
  fi
fi
if [ "$FRAME_LOCAL" = 0 ] || [ -n "${SSH_CONNECTION:-}" ]; then
  echo "Over SSH: if the connection drops, run this again (it keeps what it downloaded). Services"
  echo "that need SteamVR start with it if it isn't running now."
fi

step "1/9 input relay (keeps Bluetooth mice working in SteamVR, device roles, button maps)"
"$root/desktops.sh" relay install

step "2/9 3D mouse: SteamVR driver"
"$root/pointer/driver/build.sh"
"$root/pointer/driver/install.sh" install

step "3/9 3D mouse: pointer helper service"
"$root/pointer/helper/build.sh"
"$root/pointer/helper/run.sh" install

step "4/9 power service (turns the displays off while the headset isn't used, even on a stand)"
"$root/power/build.sh"
"$root/power/run.sh" install

step "5/9 multi-screen desktop (ft-screens), Frametop Input Settings, and Frametop Display Settings"
"$root/screens/build.sh"
"$root/setup/pyside-venv.sh"
"$root/desktops.sh" install >/dev/null
"$root/input-settings/install.sh"
"$root/display-settings/install.sh"
on_frame "sed -i 's/^POINTER=0/POINTER=1/' ~/.config/frametop.conf; grep -q '^POINTER=' ~/.config/frametop.conf || echo 'POINTER=1' >> ~/.config/frametop.conf"
echo "the launcher's Desktop entry now opens the multi-screen desktop; 3D mouse on (POINTER=1 in ~/.config/frametop.conf)"
"$root/scripts/conf-migrate.sh"

step "6/9 gaze mode (optional, experimental: the pointer goes where you look)"
gaze=0
if ask "Install gaze mode? You turn it on and calibrate it in Frametop Input Settings, on the Gaze page." y; then
  "$root/gaze/run.sh" install
  gaze=1
else
  echo "skipped. Install later with: gaze/run.sh install"
fi

# Ours is gaze mode's default once it's installed (GAZE_TRACKER=auto). Without it, gaze mode
# uses SteamVR's eye tracker.
step "7/9 our own eye tracker for gaze mode (recommended: more accurate than SteamVR's)"
if [ "$gaze" = 0 ]; then
  echo "skipped: gaze mode isn't installed. Install it later with: gaze/tracker/install.sh"
elif [ "$assume_yes" = 1 ] && ! sudo_quiet; then
  echo "skipped: it needs your password (sudo), and --yes doesn't ask. Install it later with: gaze/tracker/install.sh"
elif ask "Install our own eye tracker? Gaze mode then uses it instead of SteamVR's. Its frame grabber is a small system service, so it needs your password (sudo), and it downloads about 165 MB (numpy, OpenCV)." y; then
  if "$root/gaze/tracker/install.sh" install; then
    # Configs made before GAZE_TRACKER=auto say steam, which keeps SteamVR's.
    tracker=$(on_frame "sed -n 's/^GAZE_TRACKER=\([a-z]*\).*/\1/p' ~/.config/frametop.conf | tail -1")
    if [ "$tracker" = steam ] &&
       ask "Your settings pick SteamVR's eye tracker (GAZE_TRACKER=steam, the old default). Use ours instead?" y; then
      on_frame "sed -i 's~^GAZE_TRACKER=steam\b.*~GAZE_TRACKER=auto          # gaze service: auto = our own eye tracker when installed, else SteamVR | own | steam~' ~/.config/frametop.conf"
      tracker=auto
    fi
    if [ "$tracker" = steam ]; then
      echo "installed; your settings keep SteamVR's eye tracker (pick Own tracker on the Gaze page to use ours)"
    else
      echo "gaze mode uses our eye tracker: calibrate it once, with Calibrate on the Gaze page"
    fi
  else
    echo "our eye tracker didn't install, so gaze mode uses SteamVR's. Try again with: gaze/tracker/install.sh"
  fi
else
  echo "skipped: gaze mode uses SteamVR's eye tracker. Install ours later with: gaze/tracker/install.sh"
fi

step "8/9 Remote Access (optional: the dev box, a Fedora container with krdp, FreeRDP and TigerVNC; 1-2 GB)"
if [ "$dev_box" = 1 ] && ask "Set up the dev box for Remote Access (using the Frametop desktop from another computer)?" y; then
  if on_frame 'test -x ~/.local/bin/distrobox'; then
    echo "distrobox already installed: $(on_frame '~/.local/bin/distrobox version | head -1')"
  else
    on_frame 'set -e; mkdir -p ~/dev/src
# A tested release, so upstream changes cannot break new installs.
[ -d ~/dev/src/distrobox ] || git clone --depth 1 --branch 1.8.2.5 https://github.com/89luca89/distrobox.git ~/dev/src/distrobox
cd ~/dev/src/distrobox && ./install --prefix ~/.local'
  fi
  "$root/setup/dev-container.sh"
  "$root/remote/install.sh"
else
  echo "skipped. Install later with: ./install.sh (it asks again)"
fi

step "9/9 Bluetooth fixes (optional; they let LE mice and keyboards like the Swiftpoint Z3 reconnect)"
if [ "$bluetooth" = 1 ] && ask "Install the Bluetooth fixes? They need your password (sudo)." n; then
  "$root/setup/bluetooth/install.sh" install
else
  echo "skipped. Install later with: setup/bluetooth/install.sh install"
fi

step "Done"
cat <<'EOF'
SteamVR has to restart once, to load the 3D mouse driver and to start the input relay
before it. Restarting SteamVR closes everything open in VR, including this terminal if
it's in a VR desktop. Rebooting the headset works too.

Recommended: in Frametop Display Settings > Power, choose when the displays turn off
while the headset isn't used (for a stand or mount that covers its proximity sensor), and
turn on Stay awake while plugged in, so Steam doesn't put the headset to sleep while it
charges. The displays still turn off when you take the headset off.
EOF
if ask "Restart SteamVR now?" n; then
  on_frame 'systemctl --user restart steamvr.service'
fi
