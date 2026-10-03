#!/usr/bin/env bash
# Install Frametop with its programs built for the SteamOS host, so they run there without
# the dev box (README-host.md). It builds them with the host's own gcc (host/build.sh),
# copies Frametop with them into an install folder, checks them against the host's
# libraries, and installs from that copy, so the checkout isn't needed afterwards. The
# copy's launchers start the programs directly instead of in the container (host/patches/).
# Safe to re-run, to update: the folder is replaced each time. Remote Access needs the dev
# box: install-host-devbox.sh adds it afterwards.
# Run it on the Frame host, from a Frametop checkout; from a PC:
#   ssh -t frame 'cd frametop && ./install-host.sh'
#
# Usage: ./install-host.sh [--prefix DIR] [--yes] [--no-gaze] [--no-bluetooth] [--copy-only]
#   --prefix DIR    the install folder (default ~/.local/share/frametop/app)
#   --yes           don't ask; installs gaze mode, skips the Bluetooth fixes and the
#                   SteamVR restart
#   --no-gaze       don't install gaze mode
#   --no-bluetooth  don't offer the Bluetooth fixes
#   --copy-only     build, copy and check, but install nothing from the copy
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"

prefix=$HOME/.local/share/frametop/app assume_yes=0 gaze=1 bluetooth=1 copy_only=0
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) prefix=${2:?--prefix needs a folder}; shift ;;
    --prefix=*) prefix=${1#--prefix=} ;;
    --yes) assume_yes=1 ;;
    --no-gaze) gaze=0 ;;
    --no-bluetooth) bluetooth=0 ;;
    --copy-only) copy_only=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Only the questions read from the terminal (or whatever stdin is); the build steps get no
# input, so they can't swallow typed-ahead or piped answers.
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

[ "$FRAME_LOCAL" = 1 ] || {
  echo "Run this on the Frame host (not in a container); from a PC:" >&2
  echo "  ssh -t $FRAME_HOST 'cd frametop && ./install-host.sh'" >&2
  exit 1
}
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "run this from a Frametop git checkout" >&2; exit 1; }
case $prefix in /*) ;; *) prefix=$PWD/$prefix ;; esac
prefix=${prefix%/}
case $prefix/ in "$root"/*) echo "the install folder can't be in this checkout: $prefix" >&2; exit 2 ;; esac
# Replaced on every run, so it must be ours: missing, empty, or marked by an earlier run.
[ ! -e "$prefix" ] || [ -z "$(ls -A "$prefix")" ] || [ -f "$prefix/.frametop-host" ] ||
  { echo "$prefix exists and isn't from install-host.sh: choose another with --prefix" >&2; exit 1; }
echo "Installing on this Steam Frame into $prefix"

step "1/9 build the programs with the host's gcc (host/build.sh)"
"$root/host/build.sh"

step "2/9 copy Frametop into $prefix"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
# The checkout's files, with each program in its component's build/, where the copy's
# scripts look for it. Left out: hand tracking (deferred), the host build itself, and what
# installs or updates a checkout, which would mix the dev box build into the copy.
git -C "$root" ls-files -z |
  grep -zvE '^(hands/|host/(build|build-stub)\.sh$|host/patches/|install\.sh$|install-host\.sh$|get\.sh$)' |
  rsync -a --from0 --files-from=- --ignore-missing-args "$root/" "$stage/"
for f in screens/ft-screens pointer/helper/ft-pointer pointer/driver/driver_ft_pointer.so \
  pointer/probe/vrprobe gaze/ft-gaze gaze/ft-gazepanel power/ft-powerd gaze/tracker/ft-eyegrab; do
  install -D -m 0755 "$root/$(dirname "$f")/build-host/$(basename "$f")" "$stage/$(dirname "$f")/build/$(basename "$f")"
done
for f in "$stage"/*/build.sh "$stage"/*/*/build.sh; do
  install -m 0755 "$root/host/build-stub.sh" "$f"
done
for p in "$root"/host/patches/*.patch; do
  patch -s -d "$stage" -p1 --forward --no-backup-if-mismatch -r - < "$p" >/dev/null || {
    echo "host/patches/$(basename "$p") doesn't apply to $(sed -n 's|^+++ b/||p' "$p" | head -1) any more:" >&2
    echo "it changed upstream. Update the patch to match (README-host.md)." >&2
    exit 1
  }
done
echo "$(git -C "$root" log -1 --format='%h (%cd)' --date=short)$(git -C "$root" diff --quiet HEAD || echo ', with local changes')" \
  > "$stage/VERSION"
echo "Made by install-host.sh from $root. Replaced on every run: keep nothing of yours here." \
  > "$stage/.frametop-host"
# Into a new folder next to it first: the installed copy stays until this one checks out.
new=$prefix.new
rm -rf "$new"
mkdir -p "$new"
rsync -a "$stage/" "$new/"
echo "copied $(cat "$stage/VERSION")"

step "3/9 check the programs against the host's libraries"
"$root/host/check.sh" "$new" build
# Running programs keep their files when the old copy goes.
rm -rf "$prefix.old"
[ ! -e "$prefix" ] || mv "$prefix" "$prefix.old"
mv "$new" "$prefix"
rm -rf "$prefix.old"
[ "$copy_only" = 0 ] || { echo "copied and checked; installed nothing (--copy-only)"; exit 0; }

# The rest runs from the copy: its scripts are Frametop's own installers, and they take the
# copy's path for the services and menu entries.
cd "$prefix"

step "4/9 input relay (keeps Bluetooth mice working in SteamVR, device roles, button maps)"
./desktops.sh relay install
# SteamVR restarts don't restart the relay: one running from another tree (a checkout's
# install) would stay until a reboot. A restart keeps its virtual devices (the fd store).
if pgrep -af '[i]nput/input-relay.py' | grep -qvF "$prefix/input/"; then
  systemctl --user restart frametop-input-relay.service && echo "restarted the running relay from the copy"
fi

step "5/9 3D mouse: SteamVR driver and pointer helper service"
./pointer/driver/install.sh install 2>&1 | grep -v xdg-open
./pointer/helper/run.sh install

step "6/9 power service (turns the displays off while the headset isn't used, even on a stand)"
./power/run.sh install

step "7/9 multi-screen desktop (ft-screens), Frametop Input Settings, and Frametop Display Settings"
./setup/pyside-venv.sh ||
  echo "the settings apps need it: run $prefix/setup/pyside-venv.sh once mise is in ~/.local/bin" >&2
./desktops.sh install >/dev/null
./input-settings/install.sh
./display-settings/install.sh
# Remote Access from an earlier install elsewhere needs that tree and its dev box.
f=~/.local/share/applications/ft-remote-settings.desktop
if [ -f "$f" ] && ! grep -qF "$prefix/" "$f"; then
  ./remote/install.sh uninstall >/dev/null
  echo "removed Remote Access, installed from another folder: install-host-devbox.sh adds it from here"
fi
sed -i 's/^POINTER=0/POINTER=1/' ~/.config/frametop.conf
grep -q '^POINTER=' ~/.config/frametop.conf || echo 'POINTER=1' >> ~/.config/frametop.conf
echo "the launcher's Desktop entry now opens the multi-screen desktop; 3D mouse on (POINTER=1 in ~/.config/frametop.conf)"

step "8/9 gaze mode (optional, experimental: the pointer goes where you look)"
if [ "$gaze" = 1 ] && ask "Install gaze mode? You turn it on and calibrate it in Frametop Input Settings, on the Gaze page." y; then
  ./gaze/run.sh install
  ./setup/eyes-venv.sh ||
    echo "the own tracker needs it: run $prefix/setup/eyes-venv.sh once mise is in ~/.local/bin" >&2
else
  echo "skipped. Install later with: $prefix/gaze/run.sh install"
fi

step "9/9 Bluetooth fixes (optional; they let LE mice and keyboards like the Swiftpoint Z3 reconnect)"
if [ "$bluetooth" = 1 ] && ask "Install the Bluetooth fixes? They need your password (sudo)." n; then
  ./setup/bluetooth/install.sh install
else
  echo "skipped. Install later with: $prefix/setup/bluetooth/install.sh install"
fi

step "Done"
cat <<EOF
Installed in $prefix: the checkout isn't needed to run it. To update, run this again.
Remote Access needs the dev box: $prefix/install-host-devbox.sh adds it.

SteamVR has to restart once, to load the 3D mouse driver and to start the input relay
before it. Restarting SteamVR closes everything open in VR, including this terminal if
it's in a VR desktop. Rebooting the headset works too.
EOF
if ask "Restart SteamVR now?" n; then
  systemctl --user restart steamvr.service
fi
