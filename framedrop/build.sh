#!/usr/bin/env bash
# Build Frametop's download: framedrop/build/Frametop.zip, a "Frametop" folder that FrameDrop
# installs from a PC, or that you unpack on the headset and run (frametop-install.sh). Also
# framedrop/build/frametop.framedrop.json, the manifest an "Install with FrameDrop" button
# points at, and SHA256SUMS. Same files in, same zip out.
#
# Usage: framedrop/build.sh --tree DIR --flatpak FILE --version V [--commit SHA] [--channel C] [ZIP_URL]
#        framedrop/build.sh [ZIP_URL]
#   --tree DIR     a release: the repo at the release's commit with its programs built for the
#                  host (the build image's /src/frametop, copied out: release.yml) goes in the
#                  zip as frametop-tree.tar.zst, with the Flatpak bundle and
#                  frametop-release.json, and the installer installs them
#                  (pack/install-release.sh). A few hundred MB.
#   --flatpak FILE the bundle pack/flatpak/build.sh made, Frametop's Python runtime
#   --version V    the release's version (0.3.0, or 0.3.0-exp.1 for an experimental one)
#   --commit SHA   the commit it was built from (default: this checkout's HEAD)
#   --channel C    stable or experimental (default: experimental if V has a "-")
#   Without --tree, a few KB: the installer clones Frametop from GitHub (get.sh), for
#   testing the installer itself.
#   ZIP_URL  where the zip will be downloaded from (default: the release's asset, or for
#            a test zip, the framedrop-installer release)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
tree= flatpak= version= commit= channel=
while [ $# -gt 0 ]; do
  case $1 in
    --tree) tree=${2:?--tree needs a folder}; shift ;;
    --flatpak) flatpak=${2:?--flatpak needs a file}; shift ;;
    --version) version=${2:?--version needs a version}; shift ;;
    --commit) commit=${2:?--commit needs a commit}; shift ;;
    --channel) channel=${2:?--channel needs stable or experimental}; shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
out=$here/build
rm -rf "$out"
mkdir -p "$out"

files=("$here/installer/frametop-install.sh" "$here/installer/progress.py" "$here/installer/askpass")
if [ -n "$tree" ]; then
  [ -n "$version" ] && [ -n "$flatpak" ] || { echo "--tree needs --version and --flatpak" >&2; exit 2; }
  [ -x "$tree/install.sh" ] || { echo "$tree isn't a built Frametop tree (no install.sh)" >&2; exit 2; }
  [ -f "$flatpak" ] || { echo "no bundle at $flatpak" >&2; exit 2; }
  commit=${commit:-$(git -C "$repo" rev-parse HEAD)}
  url=${1:-https://github.com/Frametop/frametop/releases/download/v$version/Frametop.zip}
  echo "packing $tree"
  # Reproducible: sorted, no owners, one date; and the same zstd level each time.
  tar --zstd --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00Z' \
    -C "$tree" -cf "$out/frametop-tree.tar.zst" .
  cp "$flatpak" "$out/frametop.flatpak"
  python3 "$repo/pack/release-info.py" --tree-file "$out/frametop-tree.tar.zst" --flatpak-file "$out/frametop.flatpak" \
    --version "$version" --commit "$commit" ${channel:+--channel "$channel"} >"$out/frametop-release.json"
  files+=("$repo/pack/install-release.sh" "$out/frametop-release.json" "$out/frametop-tree.tar.zst" "$out/frametop.flatpak")
else
  url=${1:-https://github.com/Frametop/frametop/releases/download/framedrop-installer/Frametop.zip}
  files+=("$repo/get.sh")
fi

python3 - "$out/Frametop.zip" "${files[@]}" <<'EOF'
import os, shutil, sys, zipfile
dest, *files = sys.argv[1:]
with zipfile.ZipFile(dest, "w", allowZip64=True) as z:
    for path in files:
        name = os.path.basename(path)
        info = zipfile.ZipInfo(f"Frametop/{name}", date_time=(2026, 1, 1, 0, 0, 0))
        info.create_system = 3  # unix, so the permissions below count
        info.external_attr = (0o100755 if os.access(path, os.X_OK) else 0o100644) << 16
        # The tree and the bundle are compressed already.
        info.compress_type = zipfile.ZIP_STORED if name.endswith((".zst", ".flatpak")) else zipfile.ZIP_DEFLATED
        info.file_size = os.path.getsize(path)
        with open(path, "rb") as src, z.open(info, "w", force_zip64=True) as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
EOF
rm -f "$out/frametop-tree.tar.zst"

sha=$(sha256sum "$out/Frametop.zip" | cut -d' ' -f1)
python3 - "$url" "$sha" >"$out/frametop.framedrop.json" <<'EOF'
import json, sys
url, sha = sys.argv[1:]
print(json.dumps({
    "schema": "framedrop.install/v1",
    "name": "Frametop",
    "files": [{"url": url, "sha256": sha}],
}, indent=2))
EOF
(cd "$out" && sha256sum Frametop.zip frametop.framedrop.json ${tree:+frametop-release.json frametop.flatpak} >SHA256SUMS)
echo "built $out/Frametop.zip ($(du -h "$out/Frametop.zip" | cut -f1), sha256 $sha)"
echo "      $out/frametop.framedrop.json, $out/SHA256SUMS"
