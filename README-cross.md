# Frametop without the dev box

Frametop's native programs are normally built and run in the `dev` box, the Fedora container `setup/dev-container.sh` makes on the Frame (see README.md). The scripts here cross-compile them for the SteamOS host instead, so they run on the host directly, without the container. It's a separate set of scripts: the regular install doesn't use any of them.

## Building

```
xbuild/build.sh
```

It builds with [zig](https://ziglang.org) for the Frame host (aarch64, glibc 2.39), on any Linux, the Frame included. Each program goes into `build-cross/`, next to each folder's `build/` from the dev box build, so the two never mix.

It builds with this machine's own tools when it has them, whether that's a PC or one of the Frame's own distroboxes (an Ubuntu one, say). They are curl, bsdtar, nm, objdump, and, to build wlroots the first time, meson, ninja, pkgconf, a C compiler and wayland-scanner; `install-cross.sh` also needs git, rsync and patch. This installs them all with apt, dnf or pacman, in a distrobox into that container, and mise for zig:

```
xbuild/install-tools.sh
```

When one is missing, it says which and offers to build in the dev box on this machine instead (`setup/dev-container.sh --local`, the same box as the regular build; about 2 GB the first time). `--dev-box` builds there even when the tools are here. A PC's box is x86_64 and the Frame's is aarch64; zig builds the same programs from either.

zig is 0.16.0, the version `xbuild/mise.toml` pins, since zig's options change between releases. With [mise](https://mise.jdx.dev) installed, the scripts install and use that version themselves; a distrobox shares your home folder, so the host's mise works in it. Without mise, a zig on PATH has to be that version; in the dev box, xbuild installs Fedora's `zig` package, and stops if its version isn't the pinned one. It also installs `bsdtar` there. Both are installed by xbuild itself, so `setup/dev-container.sh`'s list stays as it is for everyone who doesn't cross-compile.

| Program | Links against on the host |
| --- | --- |
| `screens/build-cross/ft-screens` | libwayland-server, libwayland-client, libxkbcommon, libdrm, libpixman-1, libEGL, libGLESv2, libgbm, SteamVR's libopenvr_api |
| `pointer/helper/build-cross/ft-pointer`, `gaze/build-cross/ft-gaze`, `pointer/probe/build-cross/vrprobe`, `power/build-cross/ft-powerd` | SteamVR's libopenvr_api |
| `gaze/build-cross/ft-gazepanel` | libgbm, libdrm, SteamVR's libopenvr_api |
| `pointer/driver/build-cross/driver_ft_pointer.so`, `gaze/tracker/build-cross/ft-eyegrab` | libc and libm only |

None of them needs the host's libstdc++: zig links its libc++ in statically. OpenVR passes only plain types across its interfaces, so a program with its own C++ runtime works with SteamVR's.

## The link check

`build.sh` fails if any program needs a glibc symbol newer than 2.39. On the Frame, it then runs `xbuild/check.sh`, which has the host's dynamic loader resolve every program against the host's own libraries, each library and symbol version, without running anything. Built elsewhere, the check runs once they're on the Frame. A gap there, from a SteamOS too old or too new for what they were built against, stops with a FAIL line for each missing library or symbol. Then use the dev box build (`./install.sh`, README.md) instead, which builds against the container's libraries and runs the programs there.

## How it works

- `sysroot.sh` unpacks Arch Linux ARM's wayland, libxkbcommon, libdrm, pixman, libffi, wayland-protocols, libglvnd and mesa packages into `xbuild/build/alarm/sysroot`, checked against the repo databases' checksums. SteamOS is Arch-based, and on SteamOS 0.3.0 (build 20260922) these are the same versions the host has, except Mesa: SteamOS has Valve's own build (`deckard-mesa`), and the sysroot's is used only for gbm's headers and to link against libgbm, whose interface is stable. They provide headers and link-time libraries only; libc comes from zig's glibc 2.39 target.
- `wlroots.sh` builds wlroots 0.20.2 as a static library. The host has no wlroots, and ft-screens uses only its protocol side (seat, xdg-shell, linux-dmabuf, shm), so every backend, renderer and allocator is off. What's left needs wayland ≥ 1.24.0, libdrm ≥ 2.4.129, xkbcommon ≥ 1.8.0 and pixman ≥ 0.43.0 on the host.
- `openvr.sh` fetches the pinned OpenVR v2.15.6 headers and Valve's aarch64 `libopenvr_api.so`. That library has no SONAME, so linking it directly records the build machine's path to it as a dependency. The programs link against a stub instead, with the same exports and `SONAME libopenvr_api.so`, and at run time the rpath finds SteamVR's own copy in `/opt/steamvr/bin/linuxarm64`.
- The driver exports only `HmdDriverFactory` (`driver.map`), so libc++'s `operator new` and `delete` don't leak into vrserver. zig's linker has no `--exclude-libs`, which the container build uses for this.
