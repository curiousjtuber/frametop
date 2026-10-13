# Building and packaging Frametop

How Frametop is built for the Frame and shipped.
[host-and-flatpak.md](host-and-flatpak.md) is the rationale: the programs are
built for the SteamOS host and run there, the Python apps that need more than
the host's Python run in a Flatpak, and nothing on the headset is a container.
This page is the practical reference.

## The build image (`Containerfile`)

`pack/Containerfile` is the build environment: Ubuntu 24.04 (arm64, by digest),
whose glibc is the SteamOS host's version (2.39), the toolchain, the libraries
the programs link, and the test gate's Python (a uv venv of the locked dev and
tracker groups). It builds the programs with the components' own `build.sh`
scripts (`FRAME_IN_BOX=1`, so they run here instead of over SSH), exactly as a
developer builds them on the Frame, and `scripts/host-glibc.sh` checks every
program for glibc symbols newer than the host's.

wlroots 0.20, which ft-screens links statically, wants wayland,
wayland-protocols, libdrm, libxkbcommon and pixman newer than Ubuntu 24.04's.
The image builds those five from pinned tarballs into `/usr/local`, at wlroots'
minimums, which are all older than SteamOS's: a program built against them never
references a symbol the host lacks, and loads the host's copies there.

Every input is pinned: the base by digest, those libraries by version and
sha256, uv by version and sha256, OpenVR by tag and sha256 (`scripts/openvr.sh`,
and the SDK's `libopenvr_api.so` to link, since the image has no SteamVR; the
programs' rpath names SteamVR's folder first), the Python packages by `uv.lock`.

The `ft` wrapper drives it from a checkout:

```
ft dev build        # build the image (docker or podman)
ft dev shell        # a shell in it, the checkout mounted at /src/frametop
ft dev test         # the test gate inside it (just test)
ft dev run CMD...   # one command inside it
```

`FT_IMAGE` names the image (default `frametop:local`), `FT_ENGINE` the engine.
On the Frame itself, `podman build --network=host` builds it natively.

## The Python runtime (`flatpak/`)

`flatpak/io.github.frametop.Frametop.yml` is Frametop's Python runtime: KDE's
`org.kde.Platform//6.11` (Qt, Kirigami, the org.kde.desktop style, Breeze, zstd)
with PySide6 of the runtime's Qt minor, the trackers' numpy and OpenCV, and
pytest, from `uv.lock`. `flatpak/modules.py` turns the lock's apps and tracker
groups into the manifest's module, each package as the one wheel for the
runtime, with its sha256, so `pyproject.toml` and `uv lock` are where versions
change.

It holds no Frametop code. `scripts/ft-python` runs a `.py` file of the tree in
it, with the tree mounted read-only, so the settings apps, the Hand Recorder and
ft-eyes are edited and run like any script; the apps' launchers and ft-gazed go
through it. Its permissions are the table in host-and-flatpak.md. The three
settings files in `~/.config` go in as single-file bind mounts, which shapes
three details: `ft-python` makes a missing one first (`:create` would make it a
directory), a rename can't replace one, so `save_layout` writes it in place
there, and the desktop's run dir is mounted, since its socket is how the apps
tell the desktop is running. Two things learnt building it: PySide6's wheel
brings a Qt of its own, and the bindings run on the runtime's instead (the
wheel's copy is deleted; a Kirigami window loaded into it hung), and
`QQmlApplicationEngine.loadData` holds the GIL while the QML loader thread
instantiates Kirigami's plugin, which calls back into PySide and deadlocks;
`engine.load(file)`, what the apps use, releases it.

```
pack/flatpak/build.sh [--install]   # flatpak-builder -> build/frametop.flatpak
pack/flatpak/install.sh [BUNDLE]    # install a bundle, or build one when there's none
pack/flatpak/install.sh --status | --uninstall
```

On the Frame, `flatpak-builder` is the `org.flatpak.Builder` Flatpak (the host
has none); the KDE SDK is a 1 GB download the first time, and a build takes a
few minutes, since nothing compiles. `install.sh` runs `flatpak/install.sh`: a
release brings its bundle, a checkout builds one when the lock or the manifest
changed since the last build.

## Releases

A release is one file, **Frametop.zip** (a few hundred MB), attached to a GitHub
release:

- `frametop-tree.tar.zst`: the repo at the release's commit with its programs
  built, the build image's `/src/frametop` copied out (22 MB).
- `frametop.flatpak`: the Python runtime's bundle, for `flatpak install --user`.
- `frametop-release.json` (`frametop.release/v2`): version, commit, channel,
  both files' sha256, the Flatpak's app id and runtime, and the SteamOS table.
- `install-release.sh`, and the FrameDrop install window
  (`framedrop/installer`).

It installs three ways, all through the same installer: FrameDrop on a PC (Play
opens the window), `Frametop/frametop-install.sh` after unpacking on the
headset, or `get.sh --release`, which downloads it.

`install-release.sh`:

1. Checks this SteamOS build against the SteamOS table, `steamos.json` (the
   newest from main on GitHub when it can fetch it, else the release's). Tested:
   on. Not tested yet: a warning and a question (`--yes` goes on). Broken for
   this release: it stops and names the release that fixes it (`--any-steamos`
   goes on).
2. Checks both files' sha256 (a damaged one stops it, exit status 3, and
   `get.sh` downloads again), unpacks the tree to
   `~/.local/share/frametop/releases/VERSION`, puts the bundle in its
   `pack/flatpak/build/`, and writes `.frametop-release` (version, commit,
   channel, the sha256s, the app id).
3. Runs the tree's `install.sh`, which builds nothing: it installs the Flatpak
   from the bundle (and KDE's runtime from Flathub when it's missing, about 1
   GB, once: the one download), the units, the driver and the entries from the
   release's folder.
4. The release installed before stays; running its `install.sh` goes back to it.
   Older ones are removed (a release from before the Flatpak had a container of
   its own, which goes with it). `uninstall.sh` removes them all.

`pack/trial.sh` switches a Frame's live Frametop to a release and back, for
trying one.

## CI

`.github/workflows/release.yml` runs on Depot's arm64 runners
(`depot-ubuntu-24.04-arm-4`), only for a `v*` tag or by hand: no pushes or pull
requests, since the runners are paid and a fork's pull request would run on
them. It builds the image (`ft dev build`), runs the test gate inside it (`ft
dev test`: Python, C and shell), copies the built tree out and checks it (the
programs, their glibc symbols), builds the Flatpak with flatpak-builder on the
runner, runs the suites that need KDE in it (`session/tests`, the recorder's QML
test), and builds Frametop.zip (`framedrop/build.sh --tree --flatpak`). A tag
makes a draft GitHub release with the zip, its FrameDrop manifest,
`frametop-release.json`, the Flatpak bundle on its own and `SHA256SUMS`, as a
prerelease when the tag has a `-` (`v0.3.0-exp.1`); someone publishes it. A
manual run keeps the zip as an artifact for a week. The repo needs Depot's
GitHub app for the runner label to work.

`pack/test/release-test.py` tests the installer's SteamOS check and
`release-info.py` offline, on made-up files; `just test` runs it.

## What stays in a container

Remote Access over VNC: krdpserver, Xvnc and xfreerdp from the Fedora `dev`
distrobox (`setup/dev-container.sh`, `setup/container-pins.sh`), which
`install.sh` no longer sets up. It's out of this packaging's scope
(host-and-flatpak.md says why); `scripts/in-box` and `scripts/container-up.sh`
remain for it. \n
