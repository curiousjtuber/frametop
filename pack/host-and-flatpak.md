# Frametop without a container: host binaries, and a Flatpak for the Python apps

The rationale for how Frametop is built and run since 2026-11: its programs
are built for the SteamOS host and run there, the Python that needs more than
the host's `python3` runs in a Flatpak on KDE's runtime, and the OCI image is
the build environment, not the product. [design.md](design.md) is the plan it
revises (build an image in CI and run the programs from it on the Frame, in a
container); its problem analysis still holds. The conclusion changed when the
built programs' actual dependencies were checked. No podman, distrobox or
container on the headset for Frametop itself.

## What the dev container was for

`setup/dev-container.sh` made a Fedora 44 distrobox and every build and runtime
dependency went in it: the compiler, wlroots, Qt, Kirigami, PySide6, numpy,
OpenCV. The reasons given were that the host is read-only and has no compiler,
and that programs built against the container's libraries have to run in it.
Checking what the built programs actually link gives a different picture:

| Program | Links beyond libc and libstdc++ |
| --- | --- |
| ft-pointer, ft-powerd, ft-gaze, ft-reset-timer | `libopenvr_api` (SteamVR's own, by rpath) |
| ft-gazepanel, ft-handpanel, ft-spotpanel | + gbm, drm |
| ft-screens, ft-handview | wlroots, and its tree: wayland, xkbcommon, pixman, EGL/GLES, gbm, drm |
| ft-stream | curl, openssl, opus, pulse, expat, uuid |
| ft-hands, ft-camd | ncnn (built from source), jsoncpp, OpenMP; V4L2 |
| framekeyboard | cairo, pango, SDL2, Vulkan, json-c, wayland; libhangul and pyzy in its engines |
| whisper-server | Vulkan (its shaders compiled at build time with glslc) |
| driver_ft_pointer | nothing (static libstdc++; it always ran on the host) |

No Qt, no KDE, no Python in any of them. Every library in the table except
wlroots and ncnn is on the SteamOS host, with its headers, and so are gcc,
meson, ninja, cmake, pkg-config and glslc. wlroots and ncnn build as static
libraries in a few minutes; SPIRV-Headers and nlohmann/json are headers,
fetched and pinned. **The one thing that stops a container-built binary from
running on the host is glibc**: the container has a newer one. The glibc floor
below is the answer.

The Python side splits the same way:

- On the host's `/usr/bin/python3` already: ft-gazed, the input relay,
  ft-layout, ft-float, ft-steam, ft-atspi, frunner, ft-remote-settings (GTK 4
  from the host), the session's scripts.
- Needing what the host lacks: the settings apps and the Tour (PySide6,
  Kirigami), the recorders (PySide6, huggingface_hub, cryptography), ft-eyes
  (numpy, OpenCV, ncnn) and ft-voiced (sherpa-onnx, sentencepiece, numpy).

So the container provided four things: a compiler, a matched Qt + Kirigami +
PySide6, the wheels, and a Python whose version doesn't change with SteamOS. It
cost: podman and distrobox on every headset, 1 to 2 GB per container, a
container start in every launch path (`scripts/in-box`, `container-up.sh`'s
scope dance so that stopping a service doesn't stop the container), the
datagram queue length and `/tmp` and `HOME` findings in design.md, the
first-start sudo prompt (issue #9), and a KWin permission-check bypass so that
a program inside the container could capture the desktop.

## The design

Three homes, by what each program needs:

```
CI (arm64), pack/Containerfile = the build environment
┌──────────────────────────────────────────────────────┐
│ Fedora 44 base, by digest (glibc 2.43, as a SteamOS  │
│ beta's; gcc 16)                                      │
│  · the components' own build.sh, unchanged           │
│  · static wlroots, static ncnn, pinned headers       │
│  · every compile pinned to the glibc floor's symbol  │
│    versions, every program checked against the floor │
│  · the test gate (just test)                         │
└──────────────────┬───────────────────────────────────┘
                   │ Frametop.zip: the built tree, the Flatpak bundle
                   ▼
Frame
┌────────────────────────────┬───────────────────────────────┐
│ host                       │ Flatpak on org.kde.Platform   │
│  ft-screens, ft-pointer,   │  PySide6, numpy/OpenCV/ncnn,  │
│  ft-powerd, ft-gaze,       │  sherpa-onnx, the recorders'  │
│  ft-stream, ft-hands,      │  wheels, and nothing else: it │
│  framekeyboard,            │  runs the repo's .py files,   │
│  whisper-server …          │  mounted in                   │
│  the driver, services,     │   · Display and Input         │
│  host-python daemons       │     Settings, Remote Displays │
│                            │   · the Tour, the recorders   │
│                            │   · ft-eyes, ft-voiced        │
└────────────────────────────┴───────────────────────────────┘
```

**The binaries run on the host.** CI builds them in the image with the same
`build.sh` scripts a developer runs on the Frame. On the headset they are files
in the release's folder, started by the units and the session as any host
program, and `scripts/in-box` is no longer in their path.

**The Python that needs more than the host's runs in one Flatpak.** It is a
runtime, not an application: KDE's `org.kde.Platform` (Qt, Kirigami, the
desktop style, Breeze, zstd, PipeWire's tools, built together by KDE), plus
PySide6 of the same Qt minor and the wheels `uv.lock` pins. It contains none of
Frametop's code. `scripts/ft-python` runs the repo's `.py` files in it with the
repo mounted read-only, so an edit to a settings app, a recorder, ft-eyes or
ft-voiced is a file save, and the Flatpak is rebuilt only when `uv.lock` or
the manifest changes. The apps reach the host through one `host_command`
helper (`conf/fthost.py`, `recorder/common.py`), which prepends
`flatpak-spawn --host` where it prepended `distrobox-host-exec`.

**Everything else is as it was.** The host's Python keeps running the daemons.
The SteamVR driver, ft-camd and its file capabilities, the units, the launcher
entries and the session scripts were always host-side.

### What each argument of design.md maps to

| design.md's argument | With the image as product | With this design |
| --- | --- | --- |
| Every install is a build | podman load | unzip |
| No two installations alike | one image for everyone | one zip for everyone; the Flatpak's wheels pinned by sha256, its runtime by KDE's branch |
| SteamOS updates rot the build | the container's userland is frozen | the binaries' userland is the host's, which an update replaces: see "What an update can break" |
| Users need a developer ecosystem | podman + distrobox + a 1 GB container | nothing; flatpak ships with SteamOS |
| "Works on my headset" | reproduce in `ft dev shell` | the same: the image is still the build and test environment |
| Decoupled failure domains | image vs host boundary | the zip's binaries vs host boundary; the Flatpak is KDE's problem |

## The glibc floor

A program built for the host runs on every SteamOS a release supports when it
needs no symbol newer than the oldest one has. That oldest one is the floor:
SteamOS 0.4.5, glibc 2.39, with gcc 13's libstdc++ (`host_glibc_max`,
`host_glibcxx_max` and `host_cxxabi_max` in `scripts/host-glibc.sh`;
`HOST_GLIBC` in `scripts/update-check.py` is the same number). glibc is
backward compatible, so a 2.39 program also runs on the beta's 2.43.

The complication is building on something newer than the floor (a beta
Frame, or the image, whose gcc 16 is newer still). glibc keeps
every version of a symbol it ever exported, and when a function's behaviour
changes it gets a new version: on glibc 2.43 (SteamOS 0.5.7, build
20261103.6153824; the same in the Fedora 44 image) `sqrtf`, `acosf`, `asinf`,
`atan2f`, `remainder` and some fifty other libm entry points are
`@@GLIBC_2.43` by default, with the `@GLIBC_2.17` versions kept beside them
for existing binaries. A plain build there binds to the new ones and refuses to
start on 0.4.5 ("version GLIBC_2.43 not found"). Two ways out were weighed:

- **Raise the floor to 2.43.** Then every release would refuse stable 0.4.5,
  which every user runs today and was tested two days before this was written,
  until SteamOS stable moves. Not acceptable for a release.
- **Keep 2.39 and build on a 2.39 base.** Ubuntu 24.04 has glibc 2.39, but the
  parked attempt already had to rebuild five libraries from tarballs for
  wlroots 0.20, and the tree has since grown Full Keyboard's and whisper.cpp's
  dependencies; its wlroots is 0.17, which the C tests compile against. A
  second package list to keep in step with `setup/packages.txt`, and a
  toolchain two generations behind the Frame's.
- **Keep 2.39 and pin the symbol versions.** What was chosen.
  `scripts/glibc-compat.h` is a `.symver` line for every libc and libm symbol
  whose default version is newer than the floor and which has an older version
  the floor has (`__asm__(".symver sqrtf,sqrtf@GLIBC_2.17")`); every compile
  includes it first (`host_cflags` in `scripts/host-glibc.sh`, `-include`), and
  the linker binds to the older entry points. An unused line makes no
  reference. On the floor's own glibc the lines are no-ops. The header also
  undefines `__FAST_MATH__`, because with fast-math glibc's `math.h` declares
  libmvec's vector variants and gcc calls them from vectorised loops; the
  aarch64 variants that came after the floor (`tanhf`, `erff`, `powf` at
  GLIBC_2.40, in ncnn's build) have no older version at all. Without the macro
  such loops call the scalar functions, and the compiler's fast-math stays on.
  The symbols that only exist newer than the floor (`memset_explicit`, `sinpi`)
  get no line: a program that uses one fails the check, as it should.

The header is generated, not written: `scripts/glibc-compat.py --write` on the
newest glibc a build happens on (the beta Frame, or `ft dev run` in the image),
from `objdump -T` of libc and libm; its first line names the glibc it came
from, and `pack/Containerfile` runs `--check` so an image whose glibc gives
other pins fails to build. Regenerate it when a SteamOS update moves glibc, or
when raising `host_glibc_max`: at a floor equal to the build glibc the header
comes out empty, so when stable reaches 0.5.x the pins go away in one change.

The check is the other half: `host_glibc_check` runs `objdump -T` on every
program after its link, in the image and on the host alike, and fails the
build naming the program and the version that is past the floor (GLIBC_,
GLIBCXX_ and CXXABI_). On the headset, `scripts/update-check.py`'s "host
libraries" check runs `ldd` on the installed programs and names any that needs
a version this SteamOS lacks, which is what a missed pin would look like on a
stable headset. The pins can't go into a static link (`libc.a` has no symbol
versions): ft-camd, linked statically for its file capabilities, builds without
them and needs none.

The libstdc++ side has no pins: a program that needs a GLIBCXX_ version past
the floor links libstdc++ statically instead, as the driver and the testbench
always did. So far only Full Keyboard needed it, and only in the image: gcc 16
gives its C++20 atomics an entry point at GLIBCXX_3.4.35.

Verified on the beta (SteamOS 0.5.7, glibc 2.43, gcc 15.2.1): every program
builds on the host from the synced tree and binds to GLIBC_2.38 at the newest,
GLIBCXX_3.4.32 and CXXABI_1.3.15 at the newest, which is what gcc 13 on Ubuntu
24.04 produced and SteamOS 0.4.5 ran (the parked branch's test). What the
stable image's libstdc++ actually is hasn't been read on a 0.4.5 Frame; if it
turns out newer than gcc 13's, the libstdc++ floors can go up.

## Why this split

### Why the host, for the binaries

Because that's where they belong by their dependencies (the table above), and
the two that aren't on the host, wlroots and ncnn, link statically. There is
no runtime wrapper left to get wrong, and a bug report's `coredumpctl` and
`strace` work as for any host program.

What this gives up is the frozen userland. The binaries now load the host's
mesa, wayland, libinput, libxkbcommon, pixman, libdrm, curl, openssl, opus,
pulse, cairo, pango, SDL2 and Vulkan. These are libraries KWin, Steam and
gamescope need too, with stable sonames; the ones that do break their ABI
change the soname, and the program then fails to start with a clear message
rather than misbehaving. `scripts/update-check.py` lists what the installed
binaries link and flags a change after an update. The settings apps and
ft-eyes, which *would* have been sensitive to the host's Qt and Python
versions, are in the Flatpak precisely so that they aren't.

### Why a Flatpak, for the Python apps

The hard problem of running the settings apps outside Fedora is that Qt,
Kirigami, the QQC2 desktop style and PySide6 have to match each other to the
minor version. Fedora's dnf solved that in the container. The alternatives:

- **A bundled Python** (python-build-standalone plus wheels) solves ft-eyes
  in an afternoon but makes the Kirigami stack *our* build: a dozen KDE
  Frameworks modules compiled against PySide6's Qt in CI, redone at every
  PySide6 minor bump, and the usual bundled-Qt chasing of fonts, icons,
  platform theme and cursor. The largest single item of the migration.
- **The host's Qt and Kirigami with PySide6 from PyPI** costs nothing to build
  but pins PySide6 to the host's Qt minor and needs an ELF symbol-version
  patch on `libpyside6qml`. A SteamOS update to a new Qt minor breaks the apps
  until the next Frametop release. The host's Python minor moves with SteamOS
  too (3.14 on the beta), which is the same problem for ft-voiced's wheels.
- **KDE's Flatpak runtime** ships Qt 6.11, Kirigami, the desktop style and
  Breeze built together, for aarch64, maintained by KDE, on Python 3.13;
  PySide6-Essentials 6.11 has aarch64 wheels on PyPI. This is how Flathub's
  PySide applications are built. The matching problem is somebody else's.

design.md rejected Flatpak for Frametop as a whole, because the daemons live
on SteamVR, `/dev/shm`, Wayland sockets and file capabilities, and a sandbox
with that many holes isn't one. That objection stands and the daemons stay
out. For the Python apps it doesn't apply, and the holes they need are few and
were tried on a Frame (SteamOS 0.4.5 and 0.5.7, flatpak 1.15.8 and 1.16.3):

| The apps need | Flatpak flag | Tried |
| --- | --- | --- |
| the nested desktop's Wayland socket, not gamescope's | `--socket=wayland`, `WAYLAND_DISPLAY` as the socket's absolute path | yes (`krdpd` in steam-frame-utils runs so) |
| the session's private D-Bus | `--socket=session-bus`, `DBUS_SESSION_BUS_ADDRESS` passed through | by krdpd's pattern |
| ft-screens, ft-powerd, the relay, over abstract sockets; SteamVR's web socket | `--share=network` (abstract sockets belong to the network namespace) | yes: the relay answered from inside |
| `~/.config/frametop.conf`, `~/.config/frametop/`, the layout and rules files | `--filesystem` for each | standard |
| the repo's `.py` files and their modules | `--filesystem=<repo>:ro`, given by the launcher | standard |
| `desktops.sh restart`, `ft-layout`, `systemd-run`, `pkexec` for the Bluetooth script, starting `ft-gazeprobe`, voice commands | `flatpak-spawn --host`, through the existing `host_command` helper | yes |
| ft-eyes and the Eye Recorder: SteamVR's `eye-server.mmap` and ft-eyegrab's `frametop-eyes-cams` in `/dev/shm` | `--device=shm` (flatpak ≥ 1.15.6; `--device=all` does *not* mount the host's `/dev/shm`) | yes: both visible |
| ft-voiced: the microphone and its sounds, through the host's PipeWire | `--socket=pulseaudio`, `--filesystem=xdg-run/pipewire-0`; `pw-record` and `pw-play` are the runtime's | the runtime has both |
| the Hand Recorder: the headset's calibration in `/persist` | `--filesystem=/persist:ro` | standard |

ft-gazed starts ft-eyes as `scripts/ft-python gaze/tracker/ft-eyes
--watch-stdin`, a child it owns, as it did through `in-box`; `--watch-stdin`
is what ends it, so signal forwarding through bwrap isn't relied on. ft-voiced
runs as a service through the same script: the sandbox's processes are in the
unit's cgroup, so the unit's stop reaches them.

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
(base by digest, OpenVR by tag and sha256, wlroots, ncnn, SPIRV-Headers and
nlohmann/json by version and sha256, wheels by sha256), run by CI and by
`ft dev shell` alike, with the test gate inside it. What changes is what comes
out of it: a tree of built programs, not a container to ship. Its base stays
Fedora 44 because that's where every package the builds and the tests need is
already listed, and its glibc generation is the beta Frame's, so CI builds and
on-device builds go through one path, the pins.

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
  `build/` output in place (the binaries and the pinned hand models; the
  static libraries' sources and objects are left out), as the image's
  `/src/frametop` is copied out.
- `frametop.flatpak`: the Python runtime, a single-file bundle for
  `flatpak install --user`.
- `frametop-release.json`: version, commit, the sha256 of both files, the
  Flatpak's app id and runtime, the SteamOS table.
- `install-release.sh` and the FrameDrop window, unchanged in role.

A few hundred MB instead of 1.1 GB. `install-release.sh` unpacks the tree to
`~/.local/share/frametop/releases/VERSION`, puts the bundle in it, and runs the
tree's `install.sh`, which installs the Flatpak (and the KDE runtime from
Flathub when it's missing), the units, the driver, the launcher entries and the
optional parts as now, and builds nothing. The previous release stays to go
back to, as now; there are no containers or images to remove with the older
ones (a release from before this design had one, and goes with it).

A source install (`get.sh`, `install.sh` in a clone) builds the binaries on
the host with its own toolchain, and builds the Flatpak locally with
flatpak-builder (`org.flatpak.Builder` from Flathub on the Frame, which has no
flatpak-builder; slow only the first time: the KDE SDK is a 1 GB download).

## Developing

- **Binaries, on the Frame:** `screens/build.sh` and the others build on the
  host; an incremental build is seconds. `scripts/frame.sh --host` runs them
  over SSH from a PC as now. **In the image**, `ft dev shell` gives the CI
  environment.
- **Python:** edit, run. The launchers mount the checkout into the sandbox;
  nothing to rebuild. A new dependency: add it to `pyproject.toml`, `uv
  lock`, rebuild the Flatpak once (`pack/flatpak/install.sh` does when the
  lock changed).
- **Tests:** `just test` in the image for the Python suites that don't need
  Qt, the C tests, the keyboard's ctest and the shell syntax gate; the Qt
  suites run in the Flatpak (`just test-kde`, through `scripts/ft-python`), on
  the Frame and in CI.

## What an update can break

A SteamOS update replaces the host's libraries along with SteamVR, KWin and
gamescope. The binaries depend on glibc staying ≥ 2.39 (it only grows) and
on the sonames in the table above staying; `update-check.py` lists the
libraries the installed binaries link and names any that went missing, or any
program that needs a symbol version this glibc lacks. Qt and Python versions on
the host no longer matter to Frametop. The Flatpak depends on the host only for
flatpak itself, which SteamOS ships and Steam's Desktop Mode relies on, and for
the usual GPU and Wayland access flatpak arranges.

## Decisions

1. **Base image for the build:** Fedora 44 arm64 by digest, as before: every
   package the builds and tests need is listed for it, and its glibc and gcc
   are a SteamOS beta's generation.
2. **The glibc floor:** SteamOS 0.4.5's (glibc 2.39, gcc 13's libstdc++),
   kept on a newer build glibc by the generated symbol-version pins, checked
   after every link; raised only once no supported SteamOS is older.
3. **Flatpak:** app id `io.github.frametop.Frametop`, runtime
   `org.kde.Platform//6.11`, PySide6-Essentials 6.11.x, the trackers', Voice's
   and the recorders' wheels at `uv.lock`'s versions, generated into the
   manifest from the lock with their sha256. No exported desktop entries:
   the repo's launchers start it, so Plasma's menus and Steam's "Launch a
   program" see the same entries as today.
4. **Flatpak permissions:** the table above, and no more; in particular no
   `--filesystem=host`.
5. **Code location:** the repo's `.py` files stay in the tree and are
   mounted read-only at run time. The Flatpak carries interpreters and
   wheels only.
6. **Remote Access:** unchanged, container-based, opt-in setup; its
   migration is a separate decision.
7. **CI:** the image build and the test gate as now; flatpak-builder on the
   runner; `framedrop/build.sh` assembles the zip from the tree and the
   bundle.
