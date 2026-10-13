# Sourced by the build scripts, after linking: a program built here runs on the SteamOS host,
# so it may need no glibc symbol newer than the host's. On the host itself that holds by
# construction; in the build image (pack/Containerfile) it holds because the image's glibc is
# the host's version, and this is the check that keeps it so when either moves.
# HOST_GLIBC in scripts/update-check.py is the same number.
#   host_glibc_check FILE...
host_glibc_max=GLIBC_2.39
host_glibc_check() {
  local f max
  for f; do
    max=$(objdump -T "$f" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
    [ "$(printf '%s\n' "$max" "$host_glibc_max" | sort -V | tail -1)" = "$host_glibc_max" ] ||
      { echo "$f needs $max, newer than the host's $host_glibc_max" >&2; return 1; }
  done
}

# host_build_stamp PATH...: the build products cached at PATH... (static libraries, objects)
# were made by this toolchain, as build/.toolchain records (gcc and glibc). Made by another,
# a dev-container build from before the host builds, or a SteamOS update's new gcc, they are
# removed, to be made again: a container's objects aren't position-independent for the
# host's PIE link, and its libraries carry its glibc's symbol versions.
host_build_stamp() {
  local now stamp=build/.toolchain
  now="gcc $(gcc -dumpfullversion 2>/dev/null) $(ldd --version 2>/dev/null | head -1)"
  [ "$(cat "$stamp" 2>/dev/null)" = "$now" ] && return 0
  local p found=
  for p; do [ -e "$p" ] && found=1; done
  [ -z "$found" ] || echo "build products from another toolchain: making $* again" >&2
  rm -rf "$@"
  mkdir -p build
  printf '%s\n' "$now" >"$stamp"
}
