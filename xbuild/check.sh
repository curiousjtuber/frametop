#!/usr/bin/env bash
# Check the cross-compiled programs against the Frame host's own libraries: the dynamic
# loader resolves each one, every library and symbol version, without running anything.
# A gap shows up here instead of when a program starts, for example after building against
# a sysroot newer than the Frame's SteamOS (xbuild/sysroot.sh takes Arch Linux ARM's latest).
# Usage: xbuild/check.sh   (on the Frame, or from a PC over SSH; build.sh and
#                           install.sh --cross run it)
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$root/scripts/_env.sh"

on_frame_script "$FRAME_REPO" <<'EOF'
set -uo pipefail
cd "$1"
ld=/lib/ld-linux-aarch64.so.1
[ -x "$ld" ] || { echo "no $ld: run this on the Frame" >&2; exit 2; }
bad=0 n=0
for f in screens/build-cross/ft-screens pointer/helper/build-cross/ft-pointer \
  pointer/driver/build-cross/driver_ft_pointer.so pointer/probe/build-cross/vrprobe gaze/build-cross/ft-gaze \
  gaze/build-cross/ft-gazepanel power/build-cross/ft-powerd; do
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
[ "$n" -gt 0 ] || { echo "no cross-compiled programs here (xbuild/build.sh)" >&2; exit 1; }
[ "$bad" = 0 ] || { echo "The host lacks what these need: build against a sysroot no newer than its SteamOS." >&2; exit 1; }
EOF
