#!/usr/bin/env bash
# Build ft-gaze and the calibration panel ft-gazepanel on the Frame host, with its own gcc
# (gaze/build/; they run there too). In the build image (pack/Containerfile) the same build
# runs against the host's glibc version. The panel draws its text with stb_truetype (public
# domain, one header, pinned as in screens/build.sh).
# The eye tracking API (IVRInput::GetEyeTrackingDataRelativeToNow) is newer than the header
# shipped with SteamVR's samples, so this uses the pinned public header (scripts/openvr.sh).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze 'set -e; mkdir -p build/include
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include -I../pointer/common \
  -o build/ft-gaze ft-gaze.cpp $OPENVR_LIBS -lpthread
stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
[ -f build/include/stb-$stb ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" -o build/include/stb_truetype.h && touch build/include/stb-$stb; }
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include $(pkg-config --cflags gbm libdrm) \
  -o build/ft-gazepanel panel/ft-gazepanel.cpp $OPENVR_LIBS \
  $(pkg-config --libs gbm libdrm) -lpthread
host_glibc_check build/ft-gaze build/ft-gazepanel
echo "built build/ft-gaze build/ft-gazepanel"'
