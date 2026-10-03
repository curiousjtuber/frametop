# Frametop without the dev box

By default, Frametop's native programs (ft-screens, the pointer helper and its SteamVR driver, the power service, ft-gaze and its panel) are built in the `dev` box, the Fedora container `setup/dev-container.sh` makes, and run inside it (README.md). `install-host.sh` builds them with the SteamOS host's own gcc instead, so they run on the host directly, without the container, linked against exactly the libraries they run with. It's a separate set of scripts: the regular install doesn't use any of them, and none of Frametop's own files change.

It needs a SteamOS image that ships gcc and the headers of the libraries the programs use. Stable SteamOS 0.3.0 (build 20260922) and the 0.4.3 beta both have them. On an image without them, it stops and says what's missing; use `./install.sh` there.

## Installing

On the Frame, in a terminal, from a Frametop checkout (`git clone https://github.com/DeeJanuz/frametop.git ~/frametop`):

```
./install-host.sh
```

From a PC: `ssh -t frame 'cd frametop && ./install-host.sh'`.

It builds the programs (`host/build.sh`, about 30 seconds), copies Frametop with them into an install folder, `~/.local/share/frametop/app` by default (`--prefix DIR` for another), checks them against the host's libraries ([After a SteamOS update](#after-a-steamos-update)), and installs from that copy: the input relay, the 3D mouse driver and pointer helper, the power service, the multi-screen desktop, both settings apps, and, if you want them, gaze mode and the Bluetooth fixes. Afterwards the checkout isn't needed; to update, pull it and run `install-host.sh` again. The install folder is replaced each time, so keep nothing of yours there. `--copy-only` builds, copies and checks, but installs nothing.

The copy is the checkout's files, with each program in its component's `build/`, where Frametop's own scripts look for it. Only the launchers that would start a program in the dev box differ: `host/patches/` makes the session, the pointer and power services, the gaze service, check and probe, and the settings apps start them directly, and `host/build-stub.sh` stands in for each component's `build.sh`. A patch that no longer applies, after the file changed upstream, stops the install and says which; update it to match. Hand tracking (deferred) isn't copied.

`host/build.sh` uses each component's `build.sh` flags, and writes into `build-host/`, next to the dev box build's `build/`, so the two never mix. The one library the host lacks, wlroots 0.20.2 for ft-screens, it builds once as a static library in `host/build/`, with only the protocol side ft-screens uses (seat, xdg-shell, linux-dmabuf, shm): every backend, renderer and allocator is off.

## The Python apps on the host

Frametop Display Settings and Frametop Input Settings (PySide6 and Kirigami), and gaze mode's own eye tracker (`gaze/tracker/ft-eyes`, NumPy and OpenCV) aren't compiled. In the regular install they run in the dev box, which has their libraries. `install-host.sh` puts those on the host instead, each in a virtual environment made with Python 3.13 and uv from [mise](https://mise.jdx.dev), which has to be in `~/.local/bin`:

```
setup/pyside-venv.sh   # ~/.local/share/frametop/pyside
setup/eyes-venv.sh     # ~/.local/share/frametop/eyes (with gaze mode)
```

The host has Qt 6 and Kirigami, because Plasma uses them, but no PySide6. `pyside-venv.sh` installs PySide6-Essentials pinned to the host's exact Qt version and deletes the copy of Qt the wheel brings, so the bindings load the host's own Qt, the one Kirigami and the Breeze style are built against. SteamOS's Qt exports three QML engine functions under the symbol version `Qt_6` where PySide expects `Qt_6_PRIVATE_API`; `retag-versions.py` rewrites those three imports in `libpyside6qml`. `eyes-venv.sh` installs the wheels `gaze/tracker/requirements.txt` pins. Both are safe to re-run, and rebuild only when something changed: the host's Qt version (after a SteamOS update) or `requirements.txt`. `--force` rebuilds anyway.

The frame grabber the own tracker needs is built for the host too; install it as usual, with `gaze/tracker/install.sh` from the install folder (it needs `sudo`).

## What needs the dev box

Only Remote Access, which uses Fedora's krdp, FreeRDP and TigerVNC from the box. `install-host.sh` leaves it out. To add the dev box and Remote Access:

```
~/.local/share/frametop/app/install-host-devbox.sh
```

## After a SteamOS update

The programs were checked against the libraries SteamOS had when they were built. After an update, check them again:

```
~/.local/share/frametop/app/host/check.sh ~/.local/share/frametop/app build
```

It has the host's dynamic loader resolve every program, each library and symbol version, without running anything. On a FAIL, run `install-host.sh` again to rebuild them, or switch to the dev box build. `setup/pyside-venv.sh` rebuilds the settings apps' Python environment when the host's Qt version has changed.

## Back to the dev box build, or uninstall

Both installs use the same services, menu entries and driver, so the one installed last is the one that runs: `./install.sh` from the checkout installs the dev box build over this one. To uninstall, run README.md's Uninstall commands from the install folder, then delete it.
