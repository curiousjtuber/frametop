#!/usr/bin/env bash
# Build ft-gaze and the calibration panel ft-gazepanel on the Frame host, with its own gcc
# (gaze/build/; they run there too; scripts/host-glibc.sh keeps them within the host's glibc).
# The panel draws its text with stb_truetype (public domain, one header, pinned and checked
# in scripts/stb.sh).
# The eye tracking API (IVRInput::GetEyeTrackingDataRelativeToNow) is newer than the header
# shipped with SteamVR's samples, so this uses the pinned public header (scripts/openvr.sh).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze 'set -e; mkdir -p build/include
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers $host_cflags -Ibuild/include -I../pointer/common \
  -o build/ft-gaze ft-gaze.cpp $OPENVR_LIBS -lpthread
. ../scripts/stb.sh
stb_fetch build/include stb_truetype.h
g++ -std=c++17 -O2 -ffunction-sections -fdata-sections -Wl,--gc-sections -Wall -Wno-unused-parameter -Wno-missing-field-initializers $host_cflags -Ibuild/include $(pkg-config --cflags gbm libdrm) \
  -o build/ft-gazepanel panel/ft-gazepanel.cpp $OPENVR_LIBS \
  $(pkg-config --libs gbm libdrm) -lpthread
strip --strip-unneeded build/ft-gaze build/ft-gazepanel
host_glibc_check build/ft-gaze build/ft-gazepanel
echo "built build/ft-gaze build/ft-gazepanel"'
