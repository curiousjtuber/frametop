#!/usr/bin/env bash
# Install Frametop with its programs cross-compiled for the SteamOS host, so they run there
# without the dev box (README-cross.md). It builds them (xbuild/build.sh), copies Frametop
# with them into an install folder on the Frame, checks them against the host's libraries,
# and installs from that copy, so the checkout isn't needed afterwards. The copy's launchers
# start the programs directly instead of in the container (cross/patches/). Safe to re-run,
# to update: the folder is replaced each time.
# Run it from a Frametop checkout: on the Frame, in a distrobox on the Frame, or on a PC
# (over SSH to $FRAME_HOST, default "frame"). It skips what needs the dev box (Remote Access):
# install-cross-devbox.sh adds that.
#
# Usage: ./install-cross.sh [--prefix DIR] [--yes] [--no-gaze] [--no-bluetooth] [--dev-box]
#                            [--copy-only]
#   --prefix DIR    the install folder on the Frame (default ~/.local/share/frametop/app)
#   --yes           don't ask: builds in the dev box if this machine lacks the tools,
#                   installs gaze mode, skips the Bluetooth fixes and the SteamVR restart
#   --no-gaze       don't install gaze mode
#   --no-bluetooth  don't offer the Bluetooth fixes
#   --dev-box       build in the dev box even with the tools here
#   --copy-only     build, copy and check, but install nothing from the copy
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/xbuild/_host.sh"

prefix='~/.local/share/frametop/app' assume_yes=0 gaze=1 bluetooth=1 copy_only=0 build_args=()
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) prefix=${2:?--prefix needs a folder}; shift ;;
    --prefix=*) prefix=${1#--prefix=} ;;
    --yes) assume_yes=1; build_args+=(--yes) ;;
    --no-gaze) gaze=0 ;;
    --no-bluetooth) bluetooth=0 ;;
    --dev-box) build_args+=(--dev-box) ;;
    --copy-only) copy_only=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Only the questions read from the terminal (or whatever stdin is); the other steps get no
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
q() { printf %q "$1"; }

git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "run this from a Frametop git checkout" >&2; exit 1; }
for t in rsync patch; do
  command -v $t >/dev/null || { echo "install-cross.sh needs $t here (xbuild/install-tools.sh installs it)" >&2; exit 1; }
done
# The folder is the Frame's: a leading ~/ is its home folder, not this machine's.
case $prefix in
  '~/'*) prefix=$(on_host 'echo "$HOME"')/${prefix#'~/'} ;;
  /*) ;;
  *) echo "--prefix needs a full path or ~/..., a folder on the Frame" >&2; exit 2 ;;
esac
prefix=${prefix%/}
if [ "$where" != other ]; then
  case $prefix/ in "$root"/*|"$root/") echo "the install folder can't be in this checkout: $prefix" >&2; exit 2 ;; esac
fi
# Replaced on every run, so it must be ours: missing, empty, or marked by an earlier run.
on_host "[ ! -e $(q "$prefix") ] || [ -z \"\$(ls -A $(q "$prefix"))\" ] || [ -f $(q "$prefix")/.frametop-cross ]" ||
  { echo "$prefix exists and isn't from install-cross.sh: choose another with --prefix" >&2; exit 1; }

case $where in
  frame) echo "Installing on this Steam Frame into $prefix" ;;
  frame-box) echo "Building in the $box container, installing on this Steam Frame into $prefix" ;;
  other) echo "Building here, installing on $FRAME_HOST over SSH into $prefix" ;;
esac

step "1/9 cross-compile the programs (xbuild/build.sh)"
"$root/xbuild/build.sh" --no-check "${build_args[@]}" <&3

step "2/9 copy Frametop into $prefix"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
# The checkout's files, with each program in its component's build/, where the copy's
# scripts look for it. Left out: hand tracking (deferred), and what installs or updates a
# checkout, which would mix the dev box build into the copy.
git -C "$root" ls-files -z | grep -zvE '^(hands/|cross/|install\.sh$|install-cross\.sh$|get\.sh$)' |
  rsync -a --from0 --files-from=- --ignore-missing-args "$root/" "$stage/"
for f in screens/ft-screens pointer/helper/ft-pointer pointer/driver/driver_ft_pointer.so \
  pointer/probe/vrprobe gaze/ft-gaze gaze/ft-gazepanel power/ft-powerd gaze/tracker/ft-eyegrab; do
  src=$root/$(dirname "$f")/build-cross/$(basename "$f")
  [ -f "$src" ] || { echo "missing $src: xbuild/build.sh didn't build it" >&2; exit 1; }
  install -D -m 0755 "$src" "$stage/$(dirname "$f")/build/$(basename "$f")"
done
for f in "$stage"/*/build.sh "$stage"/*/*/build.sh; do
  [ "$f" = "$stage/xbuild/build.sh" ] || install -m 0755 "$root/cross/build.sh" "$f"
done
for p in "$root"/cross/patches/*.patch; do
  patch -s -d "$stage" -p1 --forward --no-backup-if-mismatch -r - < "$p" >/dev/null || {
    echo "cross/patches/$(basename "$p") doesn't apply to $(sed -n 's|^+++ b/||p' "$p" | head -1) any more:" >&2
    echo "it changed upstream. Update the patch to match (README-cross.md)." >&2
    exit 1
  }
done
echo "$(git -C "$root" log -1 --format='%h (%cd)' --date=short)$(git -C "$root" diff --quiet HEAD || echo ', with local changes')" \
  > "$stage/VERSION"
echo "Made by install-cross.sh from $root. Replaced on every run: keep nothing of yours here." \
  > "$stage/.frametop-cross"
# Into a new folder next to it first: the installed copy stays until this one checks out.
new=$prefix.new
on_host "rm -rf $(q "$new") && mkdir -p $(q "$new")"
if [ "$where" = other ]; then
  rsync -az --delete -e 'ssh -o BatchMode=yes' "$stage/" "$FRAME_HOST:$new/"
else
  rsync -a --delete "$stage/" "$new/"
fi
echo "copied $(cat "$stage/VERSION")"

step "3/9 check the programs against the Frame's own libraries"
"$root/xbuild/check.sh" "$new" build
# Running programs keep their files when the old copy goes.
on_host "set -e; rm -rf $(q "$prefix.old"); [ ! -e $(q "$prefix") ] || mv $(q "$prefix") $(q "$prefix.old")
mv $(q "$new") $(q "$prefix"); rm -rf $(q "$prefix.old")"
[ "$copy_only" = 0 ] || { echo "copied and checked; installed nothing (--copy-only)"; exit 0; }

# The rest runs on the Frame host, from the copy: its scripts are upstream's own installers,
# and they take the copy's path for the services and menu entries.
in_copy() { on_host "cd $(q "$prefix") && $1"; }

step "4/9 input relay (keeps Bluetooth mice working in SteamVR, device roles, button maps)"
in_copy './desktops.sh relay install'
# SteamVR restarts don't restart the relay: one running from another tree (a checkout's
# install) would stay until a reboot. A restart keeps its virtual devices (the fd store).
in_copy "if pgrep -af '[i]nput/input-relay.py' | grep -qv $(q "$prefix/input/"); then
  systemctl --user restart frametop-input-relay.service && echo 'restarted the running relay from the copy'
fi"

step "5/9 3D mouse: SteamVR driver and pointer helper service"
in_copy './pointer/driver/install.sh install 2>&1 | grep -v xdg-open'
in_copy './pointer/helper/run.sh install'

step "6/9 power service (turns the displays off while the headset isn't used, even on a stand)"
in_copy './power/run.sh install'

step "7/9 multi-screen desktop (ft-screens), Frametop Input Settings, and Frametop Display Settings"
in_copy './setup/pyside-venv.sh' ||
  echo "the settings apps need it: run $prefix/setup/pyside-venv.sh once mise is in ~/.local/bin" >&2
in_copy './desktops.sh install >/dev/null && ./input-settings/install.sh && ./display-settings/install.sh'
# Remote Access from an earlier install elsewhere needs that tree and its dev box.
in_copy "f=~/.local/share/applications/ft-remote-settings.desktop
if [ -f \$f ] && ! grep -q $(q "$prefix/") \$f; then
  ./remote/install.sh uninstall >/dev/null
  echo 'removed Remote Access, installed from another folder: install-cross-devbox.sh adds it from here'
fi"
in_copy "sed -i 's/^POINTER=0/POINTER=1/' ~/.config/frametop.conf; grep -q '^POINTER=' ~/.config/frametop.conf || echo 'POINTER=1' >> ~/.config/frametop.conf"
echo "the launcher's Desktop entry now opens the multi-screen desktop; 3D mouse on (POINTER=1 in ~/.config/frametop.conf)"

step "8/9 gaze mode (optional, experimental: the pointer goes where you look)"
if [ "$gaze" = 1 ] && ask "Install gaze mode? You turn it on and calibrate it in Frametop Input Settings, on the Gaze page." y; then
  in_copy './gaze/run.sh install'
  in_copy './setup/eyes-venv.sh' ||
    echo "the own tracker needs it: run $prefix/setup/eyes-venv.sh once mise is in ~/.local/bin" >&2
else
  echo "skipped. Install later with: $prefix/gaze/run.sh install"
fi

step "9/9 Bluetooth fixes (optional; they let LE mice and keyboards like the Swiftpoint Z3 reconnect)"
if [ "$bluetooth" = 1 ] && ask "Install the Bluetooth fixes? They need your password (sudo)." n; then
  on_host -t "cd $(q "$prefix") && ./setup/bluetooth/install.sh install" <&3
else
  echo "skipped. Install later with: $prefix/setup/bluetooth/install.sh install"
fi

step "Done"
cat <<EOF
Installed in $prefix: the checkout isn't needed to run it. To update, run this again.
Remote Access needs the dev box: $prefix/install-cross-devbox.sh adds it.

SteamVR has to restart once, to load the 3D mouse driver and to start the input relay
before it. Restarting SteamVR closes everything open in VR, including this terminal if
it's in a VR desktop. Rebooting the headset works too.
EOF
if ask "Restart SteamVR now?" n; then
  on_host 'systemctl --user restart steamvr.service'
fi
