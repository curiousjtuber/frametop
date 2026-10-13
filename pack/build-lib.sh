#!/bin/bash
# In the build image (pack/Containerfile): build one meson library from a pinned source
# tarball into /usr/local, and check the tarball's sha256 first.
#   build-lib NAME VERSION URL SHA256 [meson options...]
set -euo pipefail
name=$1 version=$2 url=$3 sha=$4
shift 4
work=/tmp/build-$name
rm -rf "$work"; mkdir -p "$work/src"
curl -fsSL "$url" -o "$work/src.tar"
echo "$sha  $work/src.tar" | sha256sum -c --status || { echo "$name $version does not match its pinned sha256" >&2; exit 1; }
tar xf "$work/src.tar" -C "$work/src" --strip-components=1
{ meson setup --wrap-mode=nofallback -Dbuildtype=release -Dprefix=/usr/local --libdir=lib "$@" "$work/build" "$work/src" &&
  ninja -C "$work/build"; } > "$work/build.log" 2>&1 ||
  { tail -40 "$work/build.log" >&2; echo "$name $version did not build" >&2; exit 1; }
meson install -C "$work/build" --quiet
ldconfig
rm -rf "$work"
echo "built $name $version"
