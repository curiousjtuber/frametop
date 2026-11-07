#!/usr/bin/env bash
# Build our own eye tracker's frame grabber on the Frame host, with its own gcc:
#   build/ft-eyegrab   runs as root (frametop-eyegrab.service, gaze/tracker/install.sh), so it
#                      may only need glibc symbols the host has (scripts/host-glibc.sh).
# ft-eyes itself and lab/ run in Frametop's Python runtime (scripts/ft-python, pack/flatpak),
# which brings their numpy, OpenCV and ncnn (uv.lock); nothing of theirs is built. On a PC,
# frame-job's SETUP makes build/venv from requirements.txt for the lab tools.
# Usage: gaze/tracker/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze/tracker 'set -e; mkdir -p build
. ../../scripts/host-glibc.sh
gcc -std=gnu11 -O2 -Wall -Wextra -pthread $host_cflags -o build/ft-eyegrab ft-eyegrab.c
strip --strip-unneeded build/ft-eyegrab
host_glibc_check build/ft-eyegrab
echo "built build/ft-eyegrab"'
