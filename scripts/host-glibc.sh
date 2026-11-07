# Sourced by the build scripts, from a component's folder: what keeps a program built here
# runnable on the SteamOS host (pack/host-and-flatpak.md, "The glibc floor").
#
# A program built for the host may need no glibc, libstdc++ or libgcc symbol newer than the
# oldest SteamOS a release runs on (the floor, below: SteamOS 0.4.5, glibc 2.39, gcc 13's
# libstdc++). Two cases. On that SteamOS it holds by construction. On a newer one (a beta,
# glibc 2.43 and gcc 15) and in the build image (pack/Containerfile: glibc 2.43, gcc 16) the
# compiler would take glibc's newest symbol versions, so every compile includes
# scripts/glibc-compat.h first (host_cflags, below), which binds the renamed ones to the
# versions the floor has, and host_glibc_check proves the result after linking; a program
# whose libstdc++ symbols go past the floor links libstdc++ statically instead (the driver,
# the testbench, Full Keyboard). HOST_GLIBC in scripts/update-check.py is the same number;
# scripts/glibc-compat.py reads host_glibc_max from here.
#
#   . ../scripts/host-glibc.sh          sets host_cflags (the -include; a script adds it to its
#                                       own compiles, and hands it to meson, cmake or make
#                                       explicitly: an exported CFLAGS would silently replace a
#                                       Makefile's own) and the functions
#   host_glibc_check FILE...            every FILE's newest GLIBC_, GLIBCXX_ and CXXABI_ symbol
#                                       is within the floor, else it fails and names it
#   host_build_stamp PATH...            removes the cached products PATH... (static libraries,
#                                       objects) when the toolchain or the pins changed since
#                                       they were made, so they're made again
#   host_toolchain                      prints the toolchain line the stamp records
#
# The pins can't go into a -static link (libc.a has no symbol versions): such a build leaves
# host_cflags out (hands/Makefile's ft-camd), and needs no check beyond its own.
host_glibc_max=GLIBC_2.39
host_glibcxx_max=GLIBCXX_3.4.32
host_cxxabi_max=CXXABI_1.3.15
host_glibc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
host_cflags="-include $host_glibc_dir/glibc-compat.h"

host_glibc_check() {
  local f max prefix want
  for f; do
    for prefix in GLIBC_ GLIBCXX_ CXXABI_; do
      case $prefix in
        GLIBC_) want=$host_glibc_max ;;
        GLIBCXX_) want=$host_glibcxx_max ;;
        CXXABI_) want=$host_cxxabi_max ;;
      esac
      max=$(objdump -T "$f" 2>/dev/null | grep -oE "\b$prefix[0-9.]+" | sort -uV | tail -1)
      [ -n "$max" ] || continue
      [ "$(printf '%s\n' "$max" "$want" | sort -V | tail -1)" = "$want" ] ||
        { echo "$f needs $max, newer than the floor's $want (scripts/host-glibc.sh)" >&2; return 1; }
    done
  done
}

host_toolchain() {
  echo "gcc $(gcc -dumpfullversion 2>/dev/null) $(ldd --version 2>/dev/null | head -1) compat $(sha256sum "$host_glibc_dir/glibc-compat.h" | cut -c1-12)"
}

host_build_stamp() {
  local now stamp=build/.toolchain p found=
  now=$(host_toolchain)
  [ "$(cat "$stamp" 2>/dev/null)" = "$now" ] && return 0
  for p; do [ -e "$p" ] && found=1; done
  [ -z "$found" ] || echo "build products from another toolchain or pins: making $* again" >&2
  rm -rf "$@"
  mkdir -p build
  printf '%s\n' "$now" >"$stamp"
}
