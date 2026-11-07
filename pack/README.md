# Building and packaging Frametop

How Frametop is built for the Frame and shipped.
[host-and-flatpak.md](host-and-flatpak.md) is the rationale: the programs are
built for the SteamOS host and run there, within a glibc floor, the Python apps
that need more than the host's Python run in a Flatpak, and nothing on the
headset is a container. This page is the practical reference.

## The build image (`Containerfile`)

`pack/Containerfile` is the build environment: Fedora 44 (arm64, by digest),
the toolchain, the libraries the programs link, and the test gate's Python (a
uv venv of the locked dev, tracker and voice groups). It builds the programs
with the components' own `build.sh` scripts (`FRAME_IN_BOX=1`, so they run
here instead of over SSH), exactly as a developer builds them on the Frame.
Its packages come from `setup/packages.txt` (the `both` and `image` lines),
the list the Frame's `dev` container also reads.

Its glibc (2.43) is a SteamOS beta's and its gcc (16) a generation newer still,
both past the floor a release keeps to (SteamOS 0.4.5: glibc 2.39, gcc 13's
libstdc++). So
every compile includes `scripts/glibc-compat.h` first, the symbol-version pins
`scripts/host-glibc.sh` adds (`host_cflags`), and `host_glibc_check` proves
every program after its link. The Containerfile runs
`scripts/glibc-compat.py --check` first: an image whose glibc would give other
pins fails to build. host-and-flatpak.md, "The glibc floor", has the whole
story, and when to regenerate the header.

Every input is pinned: the base by digest, wlroots, ncnn, SPIRV-Headers and
nlohmann/json by version and sha256 in their build scripts, uv by version and
sha256, OpenVR by tag and sha256 (`scripts/openvr.sh`, and the SDK's
`libopenvr_api.so` to link, since the image has no SteamVR; the programs' rpath
names SteamVR's folder first), the Python packages by `uv.lock`.

The `ft` wrapper drives it from a checkout:

```
ft dev build        # build the image (podman or docker)
ft dev shell        # a shell in it, the checkout mounted at /src/frametop
ft dev test         # the test gate inside it (just test)
ft dev run CMD...   # one command inside it
```

`FT_IMAGE` names the image (default `frametop:local`), `FT_ENGINE` the engine.
On the Frame itself, `FT_BUILD_ARGS=--network=host ft dev build` builds it
natively. `ft dev build` records the checkout's commit, and whether it had
changes in, as the image's labels and as `.ft-built` in the image's tree, which
`framedrop/build.sh` reads before it names a commit in a release.

The built programs stay in their `build/` folders under `/src/frametop`; the
libraries' sources and objects are removed, so the tree copied out of the
image (CI's "built tree" step) is what a release ships, about 110 MB with the
pinned hand models.

## The Python runtime (`flatpak/`)

`flatpak/io.github.frametop.Frametop.yml` is Frametop's Python runtime: KDE's
`org.kde.Platform//6.11` (Qt, Kirigami, the org.kde.desktop style, Breeze,
zstd, PipeWire's tools) with PySide6 of the runtime's Qt minor, the trackers'
numpy, OpenCV and ncnn, Frametop Voice's sherpa-onnx and sentencepiece, the
recorders' huggingface_hub and cryptography, and pytest, from `uv.lock`.
`flatpak/modules.py` turns the lock's apps, tracker and voice groups into the
manifest's module, each package as the one wheel for the runtime (Python 3.13,
aarch64), with its sha256, so `pyproject.toml` and `uv lock` are where versions
change.

It holds no Frametop code. `scripts/ft-python` runs a `.py` file of the tree in
it (or a package of the tree with `-m`), with the tree mounted read-only, so
the settings apps, the Tour, the recorders, ft-eyes and ft-voiced are edited
and run like any script; the apps' launchers, ft-gazed and
`frametop-voice.service` go through it. Its permissions are the table in
host-and-flatpak.md. The three settings files in `~/.config` go in as
single-file bind mounts, which shapes three details: `ft-python` makes a
missing one first (`:create` would make it a directory), a rename can't
replace one, so the apps write them in place, and the desktop's run dir is
mounted, since its socket is how the apps tell the desktop is running. Two
things learnt building it: PySide6's wheel brings a Qt of its own, and the
bindings run on the runtime's instead (the wheel's copy is deleted; a Kirigami
window loaded into it hung), and `QQmlApplicationEngine.loadData` holds the
GIL while the QML loader thread instantiates Kirigami's plugin, which calls
back into PySide and deadlocks; `engine.load(file)`, what the apps use,
releases it.

```
pack/flatpak/build.sh [--install]   # flatpak-builder -> build/frametop.flatpak
pack/flatpak/install.sh [BUNDLE]    # install a bundle, or build one when there's none
pack/flatpak/install.sh --status | --uninstall
```

On the Frame, `flatpak-builder` is the `org.flatpak.Builder` Flatpak (the host
has none; `build.sh` installs it from Flathub); the KDE SDK is a 1 GB download
the first time, and a build takes a few minutes, since nothing compiles.
`install.sh` runs `flatpak/install.sh`: a release brings its bundle, a checkout
builds one when the lock or the manifest changed since the last build.

## Releases

A release is one file, **Frametop.zip** (a few hundred MB), attached to a GitHub
release:

- `frametop-tree.tar.zst`: the repo at the release's commit with its programs
  built, the build image's `/src/frametop` copied out.
- `frametop.flatpak`: the Python runtime's bundle, for `flatpak install --user`.
- `frametop-release.json` (`frametop.release/v2`): version, commit, channel,
  both files' sha256, the Flatpak's app id and runtime, and the SteamOS table.
- `install-release.sh`, and the FrameDrop install window
  (`framedrop/installer`).

It installs three ways, all through the same installer: FrameDrop on a PC (Play
opens the window; `framedrop/README.md`), `Frametop/frametop-install.sh` after
unpacking on the headset, or `get.sh --release`, which downloads it from GitHub
(the newest stable release, or `--experimental`, `--version V`, `--zip FILE`)
and runs `install-release.sh` in the terminal.

`install-release.sh`:

1. Checks this SteamOS build (`BUILD_ID` in `/etc/os-release`) against the
   SteamOS table, `steamos.json`: the newest one, from main on GitHub, when it
   can fetch it, else the copy in the release. Tested: on. Not tested yet: a
   warning, and a question (`--yes` goes on). Broken for this release: it stops
   and names the release that fixes it (`--any-steamos` goes on). A broken build
   counts from its `from` release up to its `fixed_in`, so a release that needs
   a newer SteamOS refuses an older one, and the other way round.
2. Checks both files' sha256 (a damaged one stops it, exit status 3, and
   `get.sh` downloads again), unpacks the tree to
   `~/.local/share/frametop/releases/VERSION`, puts the bundle in its
   `pack/flatpak/build/`, and writes `.frametop-release` (version, commit,
   channel, the sha256s, the app id).
3. Runs the tree's `install.sh`, which builds nothing: it installs the Flatpak
   from the bundle (and KDE's runtime from Flathub when it's missing, about 1
   GB, once: the one download besides voice dictation's models), the units,
   the driver and the entries from the release's folder.
4. The release installed before stays; running its `install.sh` goes back to
   it and makes it `current` again. Older ones are removed (a release from
   before the Flatpak had a container of its own, which goes with it).
   `uninstall.sh` removes them all.
5. If the install stops part-way (an error, a power-off, a closed terminal),
   run the same command again: it finishes it. Until then some services may
   run from the new release and some from the old one (G7 W5 in
   `docs/charts/README.md`). `install.sh` says so when it stops early.
6. A release whose folder has fast-installed files (`scripts/fast-install`)
   isn't installed over: run `scripts/fast-install undo` in the checkout first.

`pack/trial.sh` switches a Frame's live Frametop to a release and back, for
trying one. `pack/test/release-test.py` and `pack/test/install-release-test.py`
test the installer offline, on made-up files; `just test` runs them.

## CI

`.github/workflows/check.yml` runs the test gate when started by hand (manual
only, no push or pull request trigger), on GitHub's free arm64 runner
(`ubuntu-24.04-arm`): it builds the image (`ft dev build`) and runs `ft dev
test` in it, read-only, with no secrets. It builds or publishes nothing.

`.github/workflows/release.yml` runs on Depot's arm64 runners
(`depot-ubuntu-24.04-arm-4`), only for a `v*` tag or by hand: no pushes or pull
requests, since the runners are paid and a fork's pull request would run on
them. It builds the image (`ft dev build`), runs the test gate inside it (`ft
dev test`: Python, C, keyboard and shell), copies the built tree out and checks
it (the programs, their glibc symbols against the floor), builds the Flatpak
with flatpak-builder on the runner, runs the suites that need KDE in it (`just
test-kde`), and builds Frametop.zip (`framedrop/build.sh --tree --flatpak`). A
tag makes a draft GitHub release with the zip, its FrameDrop manifest,
`frametop-release.json`, the Flatpak bundle on its own and `SHA256SUMS`, as a
prerelease when the tag has a `-` (`v0.3.0-exp.1`); someone publishes it. A
manual run keeps the zip as an artifact for a week. The repo needs Depot's
GitHub app for the runner label to work.

The repo moved from DeeJanuz/frametop to the Frametop organization on
2026-10-09, because Depot's runners need an organization. GitHub redirects the
old repo URLs; the old Pages one-liner (`deejanuz.github.io/frametop/get.sh`)
is kept by DeeJanuz/deejanuz.github.io, whose `frametop/get.sh` and
`frametop/uninstall.sh` hand over to `frametop.github.io/frametop`. A release:
merge into experimental (and main for a stable one, by merge commit), push,
tag, and publish the draft.

## What stays in a container

Remote Access over VNC: krdpserver, Xvnc and xfreerdp from the Fedora `dev`
distrobox (`setup/dev-container.sh`, `setup/container-pins.sh`), which
`install.sh` no longer sets up. It's out of this packaging's scope
(host-and-flatpak.md says why); `scripts/in-box` and `scripts/container-up.sh`
remain for it.
