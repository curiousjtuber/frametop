#!/usr/bin/env bash
# Build stream/build/ft-stream (ft-stream.cpp and host.cpp: a remote display's stream, for
# ft-screens) on the Frame host, with its own gcc, and the remote-display spikes:
# stream/build/ft-dectest (spike S1, spike/ft-dectest.cpp) and stream/build/ft-streamtest
# (spike S3, spike/ft-streamtest.cpp). In the build image (pack/Containerfile) the same build
# runs against the host's glibc version. Uses the pinned OpenVR SDK (scripts/openvr.sh), as
# ft-screens does, for IVRIPCResourceManagerClient::ImportDmabuf. ft-stream and ft-streamtest
# also need moonlight-embedded (GPLv3) at a pinned commit: its libgamestream for pairing and
# launching, and the moonlight-common-c it pins for the protocol, and its table of Windows key
# codes. ft-stream plays the host's sound with Opus and PipeWire's PulseAudio server
# (libpulse-simple). The host's pairing records are JSON, read with nlohmann/json (MIT, one
# header, pinned and checked; the host has no copy).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C stream 'set -e; mkdir -p build/include/nlohmann
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
json_ver=3.12.0 json_sha=aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63
if ! echo "$json_sha  build/include/nlohmann/json.hpp" | sha256sum -c --status 2>/dev/null; then
  curl -fsSL "https://github.com/nlohmann/json/releases/download/v$json_ver/json.hpp" -o build/include/nlohmann/json.hpp.part
  echo "$json_sha  build/include/nlohmann/json.hpp.part" | sha256sum -c --status || { echo "nlohmann/json $json_ver does not match its pinned sha256" >&2; exit 1; }
  mv build/include/nlohmann/json.hpp.part build/include/nlohmann/json.hpp
fi
host_build_stamp build/mlc build/gamestream
me=f32e415aea6797d261d6b470dcf8bf18727341c2
src=build/moonlight-embedded
mlc=$src/third_party/moonlight-common-c
if [ ! -f $src/.ft-$me ]; then
  rm -rf $src build/mlc build/gamestream
  git clone -q https://github.com/moonlight-stream/moonlight-embedded.git $src
  git -C $src checkout -q $me
  git -C $src submodule update -q --init third_party/moonlight-common-c
  git -C $mlc submodule update -q --init enet
  touch $src/.ft-$me
fi
if [ ! -f build/mlc/libmoonlight-common-c.a ]; then
  cmake -S $mlc -B build/mlc -G Ninja -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
  ninja -C build/mlc >/dev/null
fi
mkdir -p build/gamestream
for f in client http mkcert xml; do
  [ build/gamestream/$f.o -nt $src/libgamestream/$f.c ] ||
    gcc -O2 -w -fPIC -I$mlc/src -c $src/libgamestream/$f.c -o build/gamestream/$f.o
done
flags="-std=c++17 -O2 -Wall -Wno-missing-field-initializers -Ibuild/include $(pkg-config --cflags gbm libdrm egl glesv2)"
vr="$OPENVR_LIBS"
g++ $flags -o build/ft-dectest spike/ft-dectest.cpp $(pkg-config --libs gbm egl glesv2) $vr
echo "built build/ft-dectest"
g++ $flags -I$mlc/src -I$src/libgamestream -o build/ft-streamtest spike/ft-streamtest.cpp build/gamestream/*.o \
  build/mlc/libmoonlight-common-c.a build/mlc/enet/libenet.a \
  $(pkg-config --libs gbm egl glesv2 libcurl openssl expat uuid) -lpthread $vr
echo "built build/ft-streamtest"
g++ $flags -I$mlc/src -I$src/libgamestream -I$src/src -o build/ft-stream ft-stream.cpp host.cpp build/gamestream/*.o \
  build/mlc/libmoonlight-common-c.a build/mlc/enet/libenet.a \
  $(pkg-config --libs gbm egl glesv2 libcurl openssl expat uuid opus libpulse-simple) -lpthread $vr
host_glibc_check build/ft-stream build/ft-dectest build/ft-streamtest
echo "built build/ft-stream"'
