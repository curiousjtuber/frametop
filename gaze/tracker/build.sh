#!/usr/bin/env bash
# Build our own eye tracker on the Frame host, with its own gcc and Python:
#   build/ft-eyegrab   the frame grabber. It runs as root (frametop-eyegrab.service,
#                      gaze/tracker/install.sh).
#   build/venv         Python with numpy and OpenCV (requirements.txt) for ft-eyes and lab/,
#                      remade when requirements.txt changes.
# Usage: gaze/tracker/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze/tracker 'set -e; mkdir -p build
gcc -std=gnu11 -O2 -Wall -Wextra -pthread -o build/ft-eyegrab ft-eyegrab.c
echo "built build/ft-eyegrab"
if ! cmp -s requirements.txt build/venv/requirements.done; then
  rm -rf build/venv
  /usr/bin/python3 -m venv build/venv  # the host Python, not a shell one (mise, pyenv)
  build/venv/bin/pip install -q --disable-pip-version-check -r requirements.txt
  cp requirements.txt build/venv/requirements.done
fi
echo "build/venv: $(build/venv/bin/python -c "import numpy, cv2; print(\"numpy\", numpy.__version__, \"opencv\", cv2.__version__)")"'
