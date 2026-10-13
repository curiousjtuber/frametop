#!/usr/bin/env bash
# Build our own eye tracker's frame grabber on the Frame host, with its own gcc:
#   build/ft-eyegrab   runs as root (frametop-eyegrab.service, gaze/tracker/install.sh);
#                      scripts/host-glibc.sh checks it needs no glibc symbol newer than the
#                      host's, as every build here does.
# ft-eyes itself and lab/ run in Frametop's Python runtime (scripts/ft-python, pack/flatpak),
# which brings their numpy and OpenCV; nothing of theirs is built.
# Usage: gaze/tracker/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze/tracker 'set -e; mkdir -p build
. ../../scripts/host-glibc.sh
gcc -std=gnu11 -O2 -Wall -Wextra -pthread -o build/ft-eyegrab ft-eyegrab.c
host_glibc_check build/ft-eyegrab
echo "built build/ft-eyegrab"'
