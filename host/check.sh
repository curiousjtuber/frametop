#!/usr/bin/env bash
# Check the host-built programs against the Frame host's libraries: the dynamic loader
# resolves each one, every library and symbol version, without running anything. Run it
# after a SteamOS update: a gap shows up here instead of when a program starts.
# Usage: host/check.sh [TREE [DIR]]   (on the Frame host)
#   TREE  the Frametop tree (default: this one)
#   DIR   the programs' folder in each component (default: build-host; build in the copy
#         install-host.sh makes)
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${1:-$here/..}" || exit 1
dir=${2:-build-host}
ld=/lib/ld-linux-aarch64.so.1
[ -x "$ld" ] || { echo "no $ld: run this on the Frame" >&2; exit 2; }
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
[ "$n" -gt 0 ] || { echo "no host-built programs in $PWD/*/$dir (host/build.sh)" >&2; exit 1; }
if [ "$bad" = 1 ]; then
  echo "These programs don't link against this SteamOS's libraries any more: run install-host.sh" >&2
  echo "again to rebuild them, or use ./install.sh, which builds in the dev box (README.md)." >&2
  exit 1
fi
