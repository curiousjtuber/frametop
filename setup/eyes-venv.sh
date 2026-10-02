#!/usr/bin/env bash
# Create or update the Python environment that runs gaze mode's own eye tracker
# (gaze/tracker/ft-eyes) on the SteamOS host, without the dev container. Safe to re-run: it
# only rebuilds when gaze/tracker/requirements.txt has changed or it's missing.
# Usage: setup/eyes-venv.sh [--force]   (on the Frame, or from a PC over SSH)
# Needs mise in ~/.local/bin on the Frame; Python 3.13 and uv come from it.
#
# ft-eyes needs numpy and OpenCV, which the host doesn't have. This installs the wheels
# requirements.txt pins (aarch64, for glibc 2.28 and up) into ~/.local/share/frametop/eyes.
# The gaze service runs ft-eyes with it when it exists, and in the dev container otherwise.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$root/scripts/_env.sh"
"$root/scripts/sync.sh" >/dev/null

on_frame_script "$FRAME_REPO" "${1:-}" <<'EOF'
set -euo pipefail
repo=$1 force=$2
export PATH=$HOME/.local/bin:$PATH
command -v mise >/dev/null || { echo "mise not found in ~/.local/bin (https://mise.jdx.dev)" >&2; exit 1; }
venv=$HOME/.local/share/frametop/eyes
python=3.13  # numpy 2.5 needs 3.12 or newer
req=$repo/gaze/tracker/requirements.txt

check() {  # what ft-eyes imports
  "$venv/bin/python" -c 'import numpy, cv2; print(f"numpy {numpy.__version__}, OpenCV {cv2.__version__}")'
}

if [ "$force" != --force ] && cmp -s "$req" "$venv/requirements.done" && check; then
  echo "up to date: $venv"
  exit 0
fi

uv() { mise exec uv -- uv "$@"; }
mise install -q "python@$python"
py=$(mise where "python@$python")/bin/python$python
echo "building $venv (Python $python, $(grep -cvE '^\s*(#|$)' "$req") packages from gaze/tracker/requirements.txt)"
[ -n "${venv#"$HOME"/}" ] && rm -rf "$venv"
uv venv -q -p "$py" "$venv"
uv pip install -q -p "$venv/bin/python" -r "$req"
check
cp "$req" "$venv/requirements.done"
EOF
