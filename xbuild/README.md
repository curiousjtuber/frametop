# Cross-compiling

`xbuild/build.sh` builds Frametop's native programs with [zig](https://ziglang.org), in the same `dev` box the regular build uses (the Fedora container from `setup/dev-container.sh`). The programs target the SteamOS host itself (aarch64, glibc 2.39), so they run there directly instead of inside the container. They go into `build-cross/`, next to each folder's `build/`, so both builds can be on the Frame at once.

```
xbuild/build.sh
```

It runs on any Linux with distrobox and podman, the Frame included. On the host, it sets up the `dev` box on that machine (`setup/dev-container.sh --local`, the same package list) and runs itself inside it. A PC's box is x86_64 and the Frame's is aarch64; zig builds the same kind of binary from either.

zig is 0.16.0, the version `xbuild/mise.toml` pins, since zig's options change between releases. With [mise](https://mise.jdx.dev) installed, the scripts install and use that version themselves; the box shares your home folder, so the host's mise works there. Without mise, they install Fedora's `zig` package in the box, and stop if its version isn't the pinned one. The box also gets `bsdtar`. Both are installed by xbuild itself, so `setup/dev-container.sh`'s list stays as it is for everyone who doesn't cross-compile.

To use them, run `./install.sh --cross` on the Frame, or from a PC (see "Cross-compiled programs" in the top-level README). It sets `BINARIES=cross` in `~/.config/frametop.conf`, which the session script, the pointer, power and driver installers, and the gaze service read.

Built on a PC by hand, copy them to the Frame's checkout. This copies only the programs:

```
rsync -am --exclude='/xbuild/' --exclude='.git/' --include='*/' --include='build-cross/***' --exclude='*' ./ frame:frametop/
```

| Program | Links against on the host |
| --- | --- |
| `screens/build-cross/ft-screens` | libwayland-server, libwayland-client, libxkbcommon, libdrm, libpixman-1, libEGL, libGLESv2, libgbm, SteamVR's libopenvr_api |
| `pointer/helper/build-cross/ft-pointer`, `gaze/build-cross/ft-gaze`, `pointer/probe/build-cross/vrprobe`, `power/build-cross/ft-powerd` | SteamVR's libopenvr_api |
| `gaze/build-cross/ft-gazepanel` | libgbm, libdrm, SteamVR's libopenvr_api |
| `pointer/driver/build-cross/driver_ft_pointer.so` | libc and libm only |

None of them needs the host's libstdc++: zig links its libc++ in statically. OpenVR passes only plain types across its interfaces, so a program with its own C++ runtime works with SteamVR's.

## How it works

- `sysroot.sh` unpacks Arch Linux ARM's wayland, libxkbcommon, libdrm, pixman, libffi, wayland-protocols, libglvnd and mesa packages into `xbuild/build/alarm/sysroot`, checked against the repo databases' checksums. SteamOS is Arch-based, and on SteamOS 0.3.0 (build 20260922) these are the same versions the host has, except Mesa: SteamOS has Valve's own build (`deckard-mesa`), and the sysroot's is used only for gbm's headers and to link against libgbm, whose interface is stable. They provide headers and link-time libraries only; libc comes from zig's glibc 2.39 target.
- `wlroots.sh` builds wlroots 0.20.2 as a static library. The host has no wlroots, and ft-screens uses only its protocol side (seat, xdg-shell, linux-dmabuf, shm), so every backend, renderer and allocator is off. What's left needs wayland ≥ 1.24.0, libdrm ≥ 2.4.129, xkbcommon ≥ 1.8.0 and pixman ≥ 0.43.0 on the host.
- `openvr.sh` fetches the pinned OpenVR v2.15.6 headers and Valve's aarch64 `libopenvr_api.so`. That library has no SONAME, so linking it directly records the build machine's path to it as a dependency. The programs link against a stub instead, with the same exports and `SONAME libopenvr_api.so`, and at run time the rpath finds SteamVR's own copy in `/opt/steamvr/bin/linuxarm64`.
- The driver exports only `HmdDriverFactory` (`driver.map`), so libc++'s `operator new` and `delete` don't leak into vrserver. zig's linker has no `--exclude-libs`, which the container build uses for this.

`build.sh` fails if any program needs a glibc symbol newer than 2.39. After a SteamOS update, compare the host's versions (`pacman -Q wayland libxkbcommon libdrm pixman glibc`) with the sysroot's.

The settings apps aren't compiled. To run them without the container too, see `setup/pyside-venv.sh`. Then only the remote desktop needs the `dev` box, for Fedora's krdp, FreeRDP and TigerVNC.
