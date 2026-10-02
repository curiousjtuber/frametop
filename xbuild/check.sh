#!/usr/bin/env bash
# Check the cross-compiled programs against the Frame host's own libraries: the dynamic
# loader resolves each one, every library and symbol version, without running anything.
# A gap shows up here instead of when a program starts, for example after a SteamOS update,
# or after building against a sysroot newer than the Frame's SteamOS (xbuild/sysroot.sh
# takes Arch Linux ARM's latest).
# Usage: xbuild/check.sh [TREE [DIR]]
#   TREE  the Frametop tree on the Frame (default: this checkout, when it's on the Frame)
#   DIR   the programs' folder in each component (default: build-cross; build in the copy
#         install-cross.sh makes)
# Runs on the Frame host, in a container on the Frame, or from a PC over SSH ($FRAME_HOST).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/_host.sh"

tree=${1:-}
if [ -z "$tree" ]; then
  [ "$where" != other ] || { echo "usage: $0 TREE [DIR]: the Frametop tree on $FRAME_HOST" >&2; exit 2; }
  tree=$(cd "$here/.." && pwd)
fi
dir=${2:-build-cross}

on_host "set -uo pipefail
cd $(printf %q "$tree") || exit 1
dir=$(printf %q "$dir")
$(cat <<'EOF'
ld=/lib/ld-linux-aarch64.so.1
[ -x "$ld" ] || { echo "no $ld: this isn't the Frame" >&2; exit 2; }
bad=0 n=0
for f in screens/$dir/ft-screens pointer/helper/$dir/ft-pointer pointer/driver/$dir/driver_ft_pointer.so \
  pointer/probe/$dir/vrprobe gaze/$dir/ft-gaze gaze/$dir/ft-gazepanel power/$dir/ft-powerd \
  gaze/tracker/$dir/ft-eyegrab; do
  [ -e "$f" ] || continue
  n=$((n + 1))
  # LD_BIND_NOW makes the trace resolve every symbol, LD_WARN report what it can't.
  out=$(LD_TRACE_LOADED_OBJECTS=1 LD_BIND_NOW=1 LD_WARN=1 "$ld" "$f" 2>&1)
  gaps=$(grep -E "not found|undefined symbol|version .* not found" <<<"$out" | sed 's/^\s*//')
  if [ -n "$gaps" ]; then
    bad=1
    echo "FAIL  $f"; sed 's/^/        /' <<<"$gaps"
  else
    echo "ok    $f"
  fi
done
[ "$n" -gt 0 ] || { echo "no cross-compiled programs in $PWD/*/$dir (xbuild/build.sh)" >&2; exit 1; }
if [ "$bad" = 1 ]; then
  echo "These programs don't link against this SteamOS's own libraries. Use the dev box build" >&2
  echo "instead: ./install.sh from a Frametop checkout (README.md), which builds in the container." >&2
  exit 1
fi
EOF
)"
