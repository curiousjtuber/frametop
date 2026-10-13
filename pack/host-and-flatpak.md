# Frametop without a container: host binaries, and a Flatpak for the Python apps

The rationale for the next packaging step, written before the change
(2026-10-12). [design.md](design.md) is the plan it revises: build Frametop
as an OCI image in CI and run the programs from that image on the Frame, in a
container. The problem analysis there still holds. The conclusion changes:
the image stays as the **build environment**, and what it produces runs on
the SteamOS host directly, with the Python apps that need more than the
host's Python in a Flatpak on KDE's runtime. No podman, distrobox, or
container on the headset.

## What the dev container was for

`setup/dev-container.sh` makes a Fedora 44 distrobox and every build and
runtime dependency goes in it: the compiler, wlroots, Qt, Kirigami, PySide6,
numpy, OpenCV. The reasons given were that the host is read-only and has no
compiler, and that programs built against the container's libraries have to
run in it. Checking what the built programs actually link (`ldd` on the box's
builds, SteamOS 0.4.5) gives a different picture:

| Program | Links beyond libc and libstdc++ |
| --- | --- |
| ft-pointer, ft-powerd, ft-gaze | `libopenvr_api` (SteamVR's own, by rpath) |
| ft-gazepanel | + gbm, drm, expat |
| ft-screens | wlroots, and its tree: wayland, xkbcommon, pixman, EGL/GLES, gbm, drm |
| ft-stream | curl, openssl, opus, pulse, expat, uuid |
| ft-hands, ft-camd | ncnn (built from source), jsoncpp, OpenMP; V4L2 |
| driver_ft_pointer | nothing (static libstdc++; it already runs on the host) |

No Qt, no KDE, no Python in any of them. Every library in the table except
wlroots and ncnn is on the SteamOS host, with its headers, and so are gcc 15,
meson, ninja, cmake and pkg-config (the `host-build` branch built everything
there). wlroots and ncnn build as static libraries in a few minutes. **The
one thing that stops a box-built binary from running on the host is glibc**:
the box has 2.43, the host 2.39. `pointer/driver/build.sh` already deals with
that for the driver, by checking the newest `GLIBC_` symbol it needs.

The Python side splits the same way:

- On the host's `/usr/bin/python3` already: ft-gazed, the input relay,
  ft-layout, ft-float, ft-steam, ft-atspi, ft-remote-settings (GTK 4 from the
  host), the session's scripts.
- Needing what the host lacks: the three settings apps (PySide6, Kirigami)
  and ft-eyes (numpy, OpenCV).

So the container provided four things: a compiler, a matched Qt + Kirigami +
PySide6, numpy/OpenCV, and a Python whose version doesn't change with
SteamOS. It cost: podman and distrobox on every headset, 1 to 2 GB per
container (one per release, in the image plan), a container start in every
launch path (`scripts/in-box`, `container-up.sh`'s scope dance so that
stopping a service doesn't stop the container), the datagram queue length and
`/tmp` and `HOME` findings in design.md, the first-start sudo prompt (issue
#9), and a KWin permission-check bypass so that a program inside the
container could capture the desktop.

## The design

Three homes, by what each program needs:

```
CI (arm64), pack/Containerfile = the build environment
┌─────────────────────────────────────────────┐
│ Ubuntu 24.04 base (glibc 2.39 = the host's) │
│  · the components' own build.sh, unchanged  │
│  · static wlroots, static ncnn              │
│  · newest GLIBC_ symbol checked ≤ 2.39      │
│  · flatpak-builder: the Python runtime      │
└───────────────┬─────────────────────────────┘
                │ Frametop.zip
                ▼
Frame
┌───────────────────────────┬────────────────────────────────┐
│ host                      │ Flatpak on org.kde.Platform    │
│  ft-screens, ft-pointer,  │  PySide6 + numpy/OpenCV, and   │
│  ft-powerd, ft-gaze,      │  nothing else: it runs the     │
│  ft-stream, ft-hands …    │  repo's .py files, mounted in  │
│  the driver, services,    │   · Display Settings           │
│  host-python daemons      │   · Input Settings             │
│                           │   · Remote Displays            │
│                           │   · ft-eyes                    │
└───────────────────────────┴────────────────────────────────┘
```

**The binaries run on the host.** CI builds them in the image, now based on a
distribution whose glibc is the host's 2.39 (Ubuntu 24.04), with the same
`build.sh` scripts a developer runs on the Frame. Every binary gets the
driver's check: the newest glibc symbol it needs must be one the host has. On
the headset they are files in the release's folder, started by the units and
the session as any host program, and `scripts/in-box` is no longer in their
path.

**The Python that needs more than the host's runs in one Flatpak.** It is a
runtime, not an application: KDE's `org.kde.Platform` (Qt, Kirigami, the
desktop style, Breeze, built together by KDE), plus PySide6 of the same Qt
minor and the numpy/OpenCV wheels `uv.lock` pins. It contains none of
Frametop's code. The launchers run the repo's `.py` files in it with the
repo mounted read-only, so an edit to a settings app or to ft-eyes is a
file save, and the Flatpak is rebuilt only when `uv.lock` or the manifest
changes. The settings apps already live behind one `host()` helper that
prepends `distrobox-host-exec` to anything they run on the host; it prepends
`flatpak-spawn --host` instead.

**Everything else is as it was.** The host's Python keeps running the
daemons. The SteamVR driver, ft-camd and its file capabilities, the units,
the launcher entries and the session scripts were always host-side.

### What each argument of design.md maps to

| design.md's argument | With the image as product | With this design |
| --- | --- | --- |
| Every install is a build | podman load | unzip |
| No two installations alike | one image for everyone | one zip for everyone; the Flatpak's wheels pinned by sha256, its runtime by KDE's branch |
| SteamOS updates rot the build | the container's userland is frozen | the binaries' userland is the host's, which an update replaces: see "What an update can break" |
| Users need a developer ecosystem | podman + distrobox + a 1 GB container | nothing; flatpak ships with SteamOS |
| "Works on my headset" | reproduce in `ft dev shell` | the same: the image is still the build and test environment |
| Decoupled failure domains | image vs host boundary | the zip's binaries vs host boundary; the Flatpak is KDE's problem |

## Why this split

### Why the host, for the binaries

Because that's where they belong by their dependencies (the table above), and
the two that aren't on the host, wlroots and ncnn, link statically. Building
on a glibc-2.39 base in CI makes CI's binaries and a developer's host build
interchangeable. There is no runtime wrapper left to get wrong, and a bug
report's `coredumpctl` and `strace` work as for any host program.

What this gives up is the frozen userland. The binaries now load the host's
mesa, wayland, libinput, libxkbcommon, pixman, libdrm, curl, openssl, opus
and pulse. These are libraries KWin, Steam and gamescope need too, with
stable sonames; the ones that do break their ABI change the soname, and the
program then fails to start with a clear message rather than misbehaving.
`scripts/update-check.py` records the sonames the installed binaries link
and flags a change after an update. The settings apps and ft-eyes, which
*would* have been sensitive to the host's Qt and Python versions, are in the
Flatpak precisely so that they aren't.

### Why a Flatpak, for the Python apps

The hard problem of running the settings apps outside Fedora is that Qt,
Kirigami, the QQC2 desktop style and PySide6 have to match each other to the
minor version. Fedora's dnf solved that in the container. The alternatives:

- **A bundled Python** (python-build-standalone plus wheels) solves ft-eyes
  in an afternoon but makes the Kirigami stack *our* build: a dozen KDE
  Frameworks modules compiled against PySide6's Qt in CI, redone at every
  PySide6 minor bump, and the usual bundled-Qt chasing of fonts, icons,
  platform theme and cursor. The largest single item of the migration.
- **The host's Qt and Kirigami with PySide6 from PyPI** (what `host-build`
  did) costs nothing to build but pins PySide6 to the host's Qt minor and
  needs an ELF symbol-version patch on `libpyside6qml`. A SteamOS update to
  a new Qt minor breaks the apps until the next Frametop release.
- **KDE's Flatpak runtime** ships Qt 6.11, Kirigami, the desktop style and
  Breeze built together, for aarch64, maintained by KDE; PySide6-Essentials
  6.11 has aarch64 wheels on PyPI. This is how Flathub's PySide applications
  are built. The matching problem is somebody else's.

design.md rejected Flatpak for Frametop as a whole, because the daemons live
on SteamVR, `/dev/shm`, Wayland sockets and file capabilities, and a sandbox
with that many holes isn't one. That objection stands and the daemons stay
out. For the settings apps and ft-eyes it doesn't apply, and the holes they
need are few and were tried on a Frame (SteamOS 0.4.5, flatpak 1.15.8) before
this was written:

| The apps need | Flatpak flag | Tried |
| --- | --- | --- |
| the nested desktop's Wayland socket, not gamescope's | `--socket=wayland`, `WAYLAND_DISPLAY` as the socket's absolute path | yes (`krdpd` in steam-frame-utils runs so) |
| the session's private D-Bus | `--socket=session-bus`, `DBUS_SESSION_BUS_ADDRESS` passed through | by krdpd's pattern |
| ft-screens, ft-powerd, the relay, over abstract sockets | `--share=network` (abstract sockets belong to the network namespace) | yes: the relay answered from inside |
| `~/.config/frametop.conf`, `~/.config/frametop/` | `--filesystem` for both | standard |
| the repo's `.py` files and their modules | `--filesystem=<repo>:ro`, given by the launcher | standard |
| `desktops.sh restart`, `ft-layout`, `systemd-run`, `pkexec` for the Bluetooth script, starting `ft-gazeprobe` | `flatpak-spawn --host`, through the existing `host()` helper | yes |
| ft-eyes: SteamVR's `eye-server.mmap` and ft-eyegrab's `frametop-eyes-cams` in `/dev/shm` | `--device=shm` (flatpak ≥ 1.15.6; `--device=all` does *not* mount the host's `/dev/shm`) | yes: both visible |

ft-gazed starts ft-eyes as `flatpak run --command=python3 … ft-eyes
--watch-stdin`, a child it owns, as it did through `in-box`; `--watch-stdin`
is what ends it, so signal forwarding through bwrap isn't relied on.

The costs, stated:

- **A second build tool.** flatpak-builder and a manifest next to the
  Containerfile, which design.md counted against Flatpak. The manifest is
  small (one runtime, a list of wheels generated from `uv.lock` with their
  sha256) and builds in minutes, since nothing in it compiles.
- **A ~1 GB runtime download on the first install**, from Flathub, shared
  with every other KDE Flatpak on the headset (KRDC, Deskflow and krdpd use
  the same one). `install-release.sh`'s "nothing else is downloaded" holds
  only when the runtime is already there; the installer says so. Updates are
  small afterwards: the app is ~250 MB and changes only when its wheels do.
- **The runtime is pinned to a branch, not a commit.** KDE keeps a branch
  ABI-stable and retires it after about a year; moving to the next branch is
  a one-line change and a PySide6 bump, done with a release.

### Why the image stays

As the build environment, for the reasons design.md gives: one pinned recipe
(base by digest, OpenVR by tag and sha256, wlroots and ncnn by version and
sha256, wheels by sha256), run by CI and by `ft dev shell` alike, with the
test gate inside it. What changes is its base and what comes out of it: a
tree of built programs, not a container to ship.

### What stays in a container, for now

Remote Access over VNC is a chain of krdpserver, Xvnc and xfreerdp from the
dev container, with pinned FreeRDP and patched krdp (`setup/container-pins.sh`).
None of it is Frametop's code, and a Flatpak krdp server exists outside this
repo (steam-frame-utils). It is out of this change's scope:
`setup/dev-container.sh` and `scripts/in-box` stay for it, and `install.sh`
stops setting the container up by default. Remote Access documents the extra
step.

## What ships

**Frametop.zip**, as today one file for FrameDrop, `frametop-install.sh` on
the headset, or `get.sh --release`:

- `frametop-tree.tar.zst`: the repo at the release's commit with every
  `build/` output in place (the binaries, the static libraries' headers
  aren't needed), as the image's `/src/frametop` was copied out before.
- `frametop.flatpak`: the Python runtime, a single-file bundle for
  `flatpak install --user`.
- `frametop-release.json`: version, commit, the sha256 of both files, the
  Flatpak's app id and commit, the SteamOS table.
- `install-release.sh` and the FrameDrop window, unchanged in role.

About 300 to 400 MB instead of 1.1 GB. `install-release.sh` unpacks the tree
to `~/.local/share/frametop/releases/VERSION`, installs the Flatpak bundle
(and the KDE runtime from Flathub when it's missing), and runs the tree's
`install.sh`, which installs the units, the driver, the launcher entries and
the optional parts as now, and builds nothing. The previous release stays to
go back to, as now; there are no containers or images to remove with the
older ones.

A source install (`get.sh`, `install.sh` in a clone) builds the binaries on
the host with its own toolchain, as `host-build` did, and installs the
Flatpak from the release that matches its manifest, or builds it locally
with flatpak-builder when there's none (slow only the first time: the KDE
SDK is a 1 GB download).

## Developing

- **Binaries, on the Frame:** `screens/build.sh` and the others build on the
  host with the image's gcc; an incremental build is seconds. `scripts/frame.sh`
  runs them over SSH from a PC as now. **In the image**, `ft dev shell` gives
  the CI environment. **Cross-compiling** on a PC against the image's arm64
  sysroot is the fast loop for ft-screens, and now natural, since the sysroot
  is the base image.
- **Python:** edit, run. The launchers mount the checkout into the sandbox;
  nothing to rebuild. A new dependency: add it to `pyproject.toml`, `uv
  lock`, rebuild the Flatpak once.
- **Tests:** `just test` in the image for the Python suites that don't need
  Qt, the C tests and the shell syntax gate; the Qt suites run in the
  Flatpak (`flatpak run --command=pytest`), in CI and by hand.

## What an update can break

A SteamOS update replaces the host's libraries along with SteamVR, KWin and
gamescope. The binaries depend on glibc staying ≥ 2.39 (it only grows) and
on the sonames in the table above staying; `update-check.py` lists the
sonames the installed binaries link and names any that went missing. Qt and
Python versions on the host no longer matter to Frametop. The Flatpak
depends on the host only for flatpak itself, which SteamOS ships and Steam's
Desktop Mode relies on, and for the usual GPU and Wayland access flatpak
arranges.

## Decisions

1. **Base image for the build:** Ubuntu 24.04 arm64 by digest. glibc 2.39
   matches the host exactly, so the check on glibc symbols can't fail by a
   base that's too new, and its libraries are older than SteamOS's, so a
   binary never references a symbol the host lacks.
2. **Flatpak:** app id `io.github.frametop.Frametop`, runtime
   `org.kde.Platform//6.11`, PySide6-Essentials 6.11.x, numpy and
   opencv-python-headless at `uv.lock`'s versions, generated into the
   manifest from the lock with their sha256. No exported desktop entries:
   the repo's launchers start it, so Plasma's menus and Steam's "Launch a
   program" see the same entries as today.
3. **Flatpak permissions:** the table above, and no more; in particular no
   `--filesystem=host`.
4. **Code location:** the repo's `.py` files stay in the tree and are
   mounted read-only at run time. The Flatpak carries interpreters and
   wheels only.
5. **Remote Access:** unchanged, container-based, opt-in setup; its
   migration is a separate decision.
6. **CI:** the image build and the test gate as now; flatpak-builder on the
   runner; `framedrop/build.sh` assembles the zip from the tree and the
   bundle.
