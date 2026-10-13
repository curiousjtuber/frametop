#!/usr/bin/env bash
# Build the hand recorder's headset panel ft-handpanel on the Frame host, with its own gcc
# (hands/rec/build/; it runs there too). Like gaze/build.sh: the pinned public OpenVR header
# (the DMA-BUF import is newer than the header shipped with SteamVR's samples), stb_truetype
# for the text and stb_image (PNG only) for the pose pictures, at the same stb commit.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C hands/rec 'set -e; mkdir -p build/include
. ../../scripts/openvr.sh
. ../../scripts/host-glibc.sh
stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
[ -f build/include/stb-$stb ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" -o build/include/stb_truetype.h && touch build/include/stb-$stb; }
[ -f build/include/stb_image-$stb ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_image.h" -o build/include/stb_image.h && touch build/include/stb_image-$stb; }
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include $(pkg-config --cflags gbm libdrm) \
  -o build/ft-handpanel panel/ft-handpanel.cpp $OPENVR_LIBS \
  $(pkg-config --libs gbm libdrm) -lpthread
host_glibc_check build/ft-handpanel
echo "built build/ft-handpanel"'
