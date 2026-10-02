#!/usr/bin/env bash
# Cross-compile Frametop's native programs for the SteamOS host with zig. They target
# aarch64 with glibc 2.39, the host's, so they run on the Frame host itself instead of in
# the dev container. This machine's own tools build them when it has them, on any Linux,
# in a container or not (one of the Frame's own distroboxes too). Otherwise, after asking,
# they're built in the dev box, the Fedora container setup/dev-container.sh makes, on this
# machine. Then, on the Frame, check.sh checks them against the host's libraries.
# Usage: xbuild/build.sh [--dev-box] [--yes] [--no-check]
#   --dev-box   build in the dev box, even with the tools here
#   --yes       set up the dev box without asking, if it's needed
#   --no-check  skip check.sh
# Writes each program into build-cross/, next to the dev box build's build/: screens/
# build-cross/ft-screens, pointer/helper/build-cross/ft-pointer, pointer/driver/build-cross/
# driver_ft_pointer.so, pointer/probe/build-cross/vrprobe, gaze/build-cross/ft-gaze and
# ft-gazepanel, power/build-cross/ft-powerd, gaze/tracker/build-cross/ft-eyegrab.
# Downloads and intermediate builds go in xbuild/build/ (see sysroot.sh, openvr.sh,
# wlroots.sh; each runs only once).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
. "$here/_host.sh"

dev_box=0 yes=0 check=1
for arg in "$@"; do
  case $arg in
    --dev-box) dev_box=1 ;;
    --yes) yes=1 ;;
    --no-check) check=0 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# In the dev box: xbuild's extras, kept off setup/dev-container.sh's list so the box stays as
# upstream has it: bsdtar for sysroot.sh, and Fedora's zig when there's no mise for the
# pinned one.
if [ "$box" = dev ]; then
  extras=(bsdtar)
  [ -x "$(command -v mise || echo "$HOME/.local/bin/mise")" ] || extras+=(zig)
  rpm -q "${extras[@]}" >/dev/null 2>&1 || sudo dnf install -y -q "${extras[@]}"
fi

# What the build runs. wlroots.sh, until it has built wlroots once, needs meson, ninja,
# pkgconf, and a C compiler and wayland-scanner for this machine itself.
want_zig=$(sed -n 's/^zig *= *"\(.*\)"/\1/p' "$here/mise.toml")
missing=()
for t in curl bsdtar nm objdump; do command -v $t >/dev/null || missing+=("$t"); done
if [ ! -f "$here/build/wlroots-install/usr/lib/libwlroots-0.20.a" ]; then
  for t in meson ninja pkgconf cc; do command -v $t >/dev/null || missing+=("$t"); done
  command -v pkgconf >/dev/null && ! pkgconf --exists wayland-scanner && missing+=(wayland-scanner)
fi
# xbuild/_env.sh gets the pinned zig through mise, if there's mise.
[ -x "$(command -v mise || echo "$HOME/.local/bin/mise")" ] || [ "$(zig version 2>/dev/null)" = "$want_zig" ] ||
  missing+=("zig $want_zig (or mise)")

build() {
  . "$here/_env.sh"  # the pinned zig
  work=$here/build
  sysroot=$work/alarm/sysroot
  ovr=$work/openvr
  wlr=$work/wlroots-install/usr

  [ -f "$sysroot/usr/lib/pkgconfig/wayland-server.pc" ] && [ -f "$sysroot/usr/lib/pkgconfig/gbm.pc" ] &&
    [ -f "$sysroot/usr/lib/pkgconfig/egl.pc" ] || "$here/sysroot.sh"
  [ -f "$ovr/stub/libopenvr_api.so" ] || "$here/openvr.sh"
  [ -f "$wlr/lib/libwlroots-0.20.a" ] || "$here/wlroots.sh"

  target=aarch64-linux-gnu.2.39
  # Log lines (__FILE__) and debug info: keep paths repo-relative, not this machine's.
  cxx=(zig c++ -target "$target" -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers
    -ffile-prefix-map="$root/"=)
  # Linked against openvr.sh's stub; at run time the rpath finds SteamVR's own copy on the Frame.
  link_ovr=(-L"$ovr/stub" -lopenvr_api -Wl,-rpath,/opt/steamvr/bin/linuxarm64 -lpthread)
  mkdir -p "$root"/{screens,pointer/helper,pointer/driver,pointer/probe,gaze,gaze/tracker,power}/build-cross
  # ft-screens' keyboard and the gaze panel draw text with stb_truetype, at the commit
  # screens/build.sh pins; both draw with gbm, and ft-screens with EGL and GLESv2 too.
  mkdir -p "$work/include"
  stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
  [ -f "$work/include/stb-$stb" ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" \
    -o "$work/include/stb_truetype.h" && touch "$work/include/stb-$stb"; }
  gl=(-I"$work/include" -I"$sysroot/usr/include" -I"$sysroot/usr/include/libdrm")

  # vrserver loads the driver: export only HmdDriverFactory, not libc++'s operator new and
  # delete (zig's linker has no --exclude-libs, so a version script does it).
  "${cxx[@]}" -fPIC -shared -fvisibility=hidden -Wl,--version-script,"$here/driver.map" -I"$ovr/include" \
    -o "$root/pointer/driver/build-cross/driver_ft_pointer.so" "$root/pointer/driver/driver_ft_pointer.cpp" -lpthread
  "${cxx[@]}" -I"$ovr/include" -I"$root/pointer/common" \
    -o "$root/pointer/helper/build-cross/ft-pointer" "$root/pointer/helper/ft-pointer.cpp" "${link_ovr[@]}"
  "${cxx[@]}" -I"$ovr/include" -I"$root/pointer/common" \
    -o "$root/gaze/build-cross/ft-gaze" "$root/gaze/ft-gaze.cpp" "${link_ovr[@]}"
  "${cxx[@]}" -I"$ovr/include" -I"$root/pointer/common" \
    -o "$root/pointer/probe/build-cross/vrprobe" "$root/pointer/probe/vrprobe.cpp" "${link_ovr[@]}"
  "${cxx[@]}" -I"$ovr/include" "${gl[@]}" -o "$root/gaze/build-cross/ft-gazepanel" "$root/gaze/panel/ft-gazepanel.cpp" \
    -L"$sysroot/usr/lib" -lgbm -ldrm "${link_ovr[@]}"
  "${cxx[@]}" -I"$ovr/include" -o "$root/power/build-cross/ft-powerd" "$root/power/ft-powerd.cpp" "${link_ovr[@]}"
  # Our own eye tracker's frame grabber (gaze/tracker/build.sh's flags).
  zig cc -target "$target" -std=gnu11 -O2 -Wall -Wextra -pthread -ffile-prefix-map="$root/"= \
    -o "$root/gaze/tracker/build-cross/ft-eyegrab" "$root/gaze/tracker/ft-eyegrab.c"

  # ft-screens: wlroots linked in statically; wayland, xkbcommon, libdrm, pixman, EGL, GLESv2
  # and gbm are the host's.
  obj=$work/screens
  mkdir -p "$obj"
  zig cc -target "$target" -std=c11 -O2 -Wall -Wno-unused-parameter -ffile-prefix-map="$root/"= \
    -I"$wlr/include/wlroots-0.20" -I"$sysroot/usr/include" -I"$sysroot/usr/include/libdrm" \
    -I"$sysroot/usr/include/pixman-1" -c -o "$obj/compositor.o" "$root/screens/compositor.c"
  for f in vr keyboard handcut; do
    "${cxx[@]}" -I"$ovr/include" "${gl[@]}" -c -o "$obj/$f.o" "$root/screens/$f.cpp"
  done
  "${cxx[@]}" -o "$root/screens/build-cross/ft-screens" "$obj"/{compositor,vr,keyboard,handcut}.o \
    "$wlr/lib/libwlroots-0.20.a" -L"$sysroot/usr/lib" -lwayland-server -lwayland-client \
    -lxkbcommon -ldrm -lpixman-1 -lEGL -lGLESv2 -lgbm -lm -lrt "${link_ovr[@]}"

  # The host has glibc 2.39: anything newer won't load there.
  for f in screens/build-cross/ft-screens pointer/helper/build-cross/ft-pointer \
    pointer/driver/build-cross/driver_ft_pointer.so pointer/probe/build-cross/vrprobe gaze/build-cross/ft-gaze \
    gaze/build-cross/ft-gazepanel power/build-cross/ft-powerd gaze/tracker/build-cross/ft-eyegrab; do
    max=$(objdump -T "$root/$f" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
    [ "$(printf '%s\n' "$max" GLIBC_2.39 | sort -V | tail -1)" = GLIBC_2.39 ] ||
      { echo "$f needs $max, newer than the host's glibc 2.39" >&2; exit 1; }
    echo "built $f (newest glibc symbol: $max)"
  done
}

if [ "$box" != dev ] && { [ "$dev_box" = 1 ] || [ ${#missing[@]} -gt 0 ]; }; then
  if [ ${#missing[@]} -gt 0 ]; then
    echo "This machine lacks what the cross build needs: ${missing[*]}"
    echo "xbuild/install-tools.sh installs them (apt, dnf or pacman)."
  fi
  [ -z "$box" ] || { echo "Install them in this container ($box), or run xbuild/build.sh outside it to build in the dev box." >&2; exit 1; }
  if [ "$yes" = 0 ]; then
    [ -t 0 ] || { echo "Build in the dev box instead, a Fedora container on this machine? --yes does." >&2; exit 1; }
    read -r -p "Build in the dev box instead? It's a Fedora container on this machine (about 2 GB the first time). [Y/n] " answer || answer=n
    [[ ${answer:-y} =~ ^[Yy] ]] || exit 1
  fi
  "$root/setup/dev-container.sh" --local
  distrobox=$HOME/.local/bin/distrobox
  [ -x "$distrobox" ] || distrobox=$(command -v distrobox)
  # podman needs the real runtime dir and user bus, also from a nested desktop's terminal.
  env XDG_RUNTIME_DIR="/run/user/$(id -u)" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    "$distrobox" enter dev -- "$here/build.sh" --no-check
elif [ ${#missing[@]} -gt 0 ]; then
  echo "The dev box lacks what the cross build needs: ${missing[*]}" >&2
  exit 1
else
  build
fi

# The build machine's libraries say nothing about the host's: check against those, on the Frame.
if [ "$check" = 1 ]; then
  if [ "$where" = other ]; then
    echo "built; once they're on the Frame, xbuild/check.sh checks them against its libraries"
  else
    "$here/check.sh"
  fi
fi
