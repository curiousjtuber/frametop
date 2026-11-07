#!/usr/bin/env bash
# Build hand tracking on the Frame host, with the gcc, cmake and libraries its SteamOS image
# ships (jsoncpp, OpenMP), into hands/build/: ft-camd and ft-hands, and with --tools also
# ft-handreplay and ft-ringplay. The first build fetches ncnn and builds it (a few minutes);
# NCNN=DIR, an ncnn install already on the Frame, skips that. It also fetches the fine-tuned
# hand models (hands/models.sh) into hands/models/student, which ft-hands prefers.
# scripts/host-glibc.sh keeps ft-hands (and ncnn, built with the same pins) within the host's
# glibc; ft-camd is linked statically and gets no pins (hands/Makefile).
# A rebuilt ft-camd has lost its capabilities: hands/run.sh caps sets them again.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
targets=all
[ "${1:-}" = --tools ] && targets="all tools"
"$root/scripts/sync.sh" >/dev/null
"$root/hands/models.sh" fetch
exec "$root/scripts/frame.sh" --host -C hands "set -e
. ../scripts/host-glibc.sh
host_build_stamp build/ncnn build/ft-camd build/ft-hands build/ft-handreplay build/ft-ringplay build/sides-test build/pinch-test build/flagbuf-test
make -s ${NCNN:+NCNN=$NCNN} FT_COMPAT=\"\$host_cflags\" $targets
host_glibc_check build/ft-hands
echo built \$(ls build/ft-* | tr '\n' ' ')"
