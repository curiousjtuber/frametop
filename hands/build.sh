#!/usr/bin/env bash
# Build hand tracking on the Frame host, with the gcc, cmake and libraries its SteamOS image
# ships (jsoncpp, OpenMP), into hands/build/: ft-camd and ft-hands, and with --tools also
# ft-handreplay and ft-ringplay. The first build fetches ncnn and builds it (a few minutes);
# NCNN=DIR, an ncnn install already on the Frame, skips that. It also makes build/venv, the
# host's Python with NumPy, OpenCV and huggingface_hub (requirements.txt) for hands/tools and
# the hand recorder's upload, remade when requirements.txt changes.
# A rebuilt ft-camd has lost its capabilities: hands/run.sh caps sets them again.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
targets=all
[ "${1:-}" = --tools ] && targets="all tools"
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C hands "set -e
make -s ${NCNN:+NCNN=$NCNN} $targets && echo built \$(ls build/ft-* | tr '\n' ' ')
if ! cmp -s requirements.txt build/venv/requirements.done; then
  rm -rf build/venv
  /usr/bin/python3 -m venv build/venv  # the host's Python, not a shell's (mise, pyenv)
  build/venv/bin/pip install -q --disable-pip-version-check -r requirements.txt
  cp requirements.txt build/venv/requirements.done
fi
echo \"build/venv: \$(build/venv/bin/python -c 'import numpy, cv2, huggingface_hub; print(\"numpy\", numpy.__version__, \"opencv\", cv2.__version__, \"huggingface_hub\", huggingface_hub.__version__)')\""
