#!/usr/bin/env bash
# Build Frametop Voice's whisper.cpp server on the Frame host, with its own gcc, cmake, glslc
# and Vulkan headers (or in the build image, for the host: scripts/host-glibc.sh):
#   build/bin/whisper-server   whisper.cpp's server on the GPU (Vulkan), for wake word commands,
#                              from whisper.cpp at a fixed commit, linked statically.
# ggml's Vulkan shaders need SPIRV-Headers (header-only), which the host lacks: a pinned
# release is fetched, checked by sha256, and installed into build/spirv-headers.
# ft-voiced itself runs in Frametop's Python runtime (scripts/ft-python, pack/flatpak), which
# brings its sherpa-onnx, sentencepiece and numpy (uv.lock's voice group); nothing of its is
# built. The models aren't built either: voice/models.sh fetches them on install.
# Usage: voice/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C voice 'set -e; mkdir -p build/bin
. ../scripts/host-glibc.sh
commit=d09f61a708f3487afa956ff578e60eae5e7a233c  # whisper.cpp master, 2026-09-24 (frame-voice used it)
src=build/whisper.cpp
host_build_stamp $src/build
spirv_ver=vulkan-sdk-1.4.341.0 spirv_sha=cab0a654c4917e16367483296b44cdb1d614e3120c721beafcd37e3a8580486c
spirv=$PWD/build/spirv-headers
if [ ! -f "$spirv/install/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake" ]; then
  rm -rf "$spirv"; mkdir -p "$spirv/src"
  curl -fsSL "https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/$spirv_ver.tar.gz" -o "$spirv/src.tar.gz"
  echo "$spirv_sha  $spirv/src.tar.gz" | sha256sum -c --status || { echo "SPIRV-Headers $spirv_ver does not match its pinned sha256" >&2; exit 1; }
  tar xzf "$spirv/src.tar.gz" -C "$spirv/src" --strip-components=1
  cmake -S "$spirv/src" -B "$spirv/build" -G Ninja -DCMAKE_INSTALL_PREFIX="$spirv/install" -DSPIRV_HEADERS_ENABLE_TESTS=OFF >/dev/null
  cmake --install "$spirv/build" >/dev/null
fi
if [ "$(git -C $src rev-parse HEAD 2>/dev/null)" != $commit ]; then
  rm -rf $src
  git init -q $src
  git -C $src fetch -q --depth 1 https://github.com/ggml-org/whisper.cpp.git $commit
  git -C $src checkout -q FETCH_HEAD
fi
# For the Frame: Armv9.2 with SVE2, i8mm, dot product and fp16 (Cortex-X925 and A720).
cmake -S $src -B $src/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv9.2-a+dotprod+i8mm+sve2+fp16 \
  -DCMAKE_C_FLAGS="-mtune=cortex-a720 $host_cflags" -DCMAKE_CXX_FLAGS="-mtune=cortex-a720 -I$spirv/install/include $host_cflags" \
  -DCMAKE_PREFIX_PATH="$spirv/install" -DWHISPER_BUILD_TESTS=OFF -DWHISPER_SDL2=OFF >/dev/null
cmake --build $src/build --target whisper-server
install -m 755 $src/build/bin/whisper-server build/bin/whisper-server
host_glibc_check build/bin/whisper-server
echo "built build/bin/whisper-server (whisper.cpp ${commit:0:7})"'
