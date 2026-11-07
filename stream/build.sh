#!/usr/bin/env bash
# Build stream/build/ft-stream (ft-stream.cpp and host.cpp: a remote display's stream, for
# ft-screens) on the Frame host, with its own gcc (scripts/host-glibc.sh keeps it within the
# host's glibc; the build image runs the same build). With --spikes, also the remote-display
# spikes, after it (so a broken spike can't hold ft-stream back): stream/build/ft-dectest
# (spike S1, spike/ft-dectest.cpp) and stream/build/ft-streamtest (spike S3,
# spike/ft-streamtest.cpp, on host.cpp too). Releases and fast-install build only ft-stream.
# Uses the pinned OpenVR SDK (scripts/openvr.sh), as ft-screens does, for
# IVRIPCResourceManagerClient::ImportDmabuf. ft-stream and ft-streamtest
# also need moonlight-embedded (GPLv3) at a pinned commit: its libgamestream for pairing and
# launching, and the moonlight-common-c it pins for the protocol, and its table of Windows key
# codes. ft-stream plays the host's sound with Opus and PipeWire's PulseAudio server
# (libpulse-simple), and sends the Frame's microphone back the same way. moonlight-mic.patch adds
# that to moonlight-common-c (LiSendMicrophoneOpusData), and moonlight-hostin.patch the host's
# keyboard and mouse (docs/host-input.md); the checkout is made again when either changes.
# The host's pairing records are JSON, read with nlohmann/json (MIT, one header, pinned and
# checked by sha256: the host has no copy).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
spikes=0
[ "${1:-}" = --spikes ] && spikes=1
exec "$root/scripts/frame.sh" --host -C stream "spikes=$spikes"'; set -e; mkdir -p build/include/nlohmann
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
mark=$me-$(cat moonlight-mic.patch moonlight-hostin.patch | sha256sum | cut -c1-12)
if [ ! -f $src/.ft-$mark ]; then
  rm -rf $src build/mlc build/gamestream
  # Only this revision and its pinned submodules are build inputs, not their history.
  git init -q $src
  git -C $src fetch -q --depth 1 https://github.com/moonlight-stream/moonlight-embedded.git $me
  git -C $src checkout -q --detach FETCH_HEAD
  git -C $src submodule update -q --init --depth 1 third_party/moonlight-common-c
  git -C $mlc submodule update -q --init --depth 1 enet
  git -C $mlc apply "$PWD/moonlight-mic.patch"
  git -C $mlc apply "$PWD/moonlight-hostin.patch"
  touch $src/.ft-$mark
fi
if [ ! -f build/mlc/libmoonlight-common-c.a ]; then
  cmake -S $mlc -B build/mlc -G Ninja -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$host_cflags" >/dev/null
  ninja -C build/mlc >/dev/null
fi
mkdir -p build/gamestream
for f in client http mkcert xml; do
  [ build/gamestream/$f.o -nt $src/libgamestream/$f.c ] ||
    gcc -O2 -w -fPIC $host_cflags -I$mlc/src -c $src/libgamestream/$f.c -o build/gamestream/$f.o
done
flags="-std=c++17 -O2 -Wall -Wno-missing-field-initializers $host_cflags -Ibuild/include $(pkg-config --cflags gbm libdrm egl glesv2)"
vr="$OPENVR_LIBS"
g++ $flags -I$mlc/src -I$src/libgamestream -I$src/src -o build/ft-stream ft-stream.cpp host.cpp build/gamestream/*.o \
  build/mlc/libmoonlight-common-c.a build/mlc/enet/libenet.a \
  $(pkg-config --libs gbm egl glesv2 libcurl openssl expat uuid opus libpulse-simple) -lpthread $vr
strip --strip-unneeded build/ft-stream
host_glibc_check build/ft-stream
echo "built build/ft-stream"
[ $spikes = 1 ] || exit 0
g++ $flags -o build/ft-dectest spike/ft-dectest.cpp $(pkg-config --libs gbm egl glesv2) $vr
g++ $flags -I$mlc/src -I$src/libgamestream -o build/ft-streamtest spike/ft-streamtest.cpp host.cpp build/gamestream/*.o \
  build/mlc/libmoonlight-common-c.a build/mlc/enet/libenet.a \
  $(pkg-config --libs gbm egl glesv2 libcurl openssl expat uuid) -lpthread $vr
strip --strip-unneeded build/ft-dectest build/ft-streamtest
host_glibc_check build/ft-dectest build/ft-streamtest
echo "built build/ft-dectest build/ft-streamtest"'
