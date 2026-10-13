# Working on Frametop

Rules for people and coding agents changing this repo. The README covers what Frametop is and how to install it; `docs/reference.md` covers each component, and `docs/design.md` records how SteamVR on the Frame behaves and why things are built the way they are. Read its notes on SteamVR before changing how the screens, the pointer, or the input relay talk to SteamVR.

## Two ways to run the scripts

Every script works in both modes, and must keep working in both:

- On the Frame (SteamOS, VR variant), commands run locally, in this checkout.
- From a PC over SSH, the repo is synced to `~/dev/frametop` on the Frame (`scripts/sync.sh`), and commands run there. `scripts/_env.sh` works out which mode applies (`FRAME_LOCAL`, `FRAME_HOST`, `FRAME_REPO`).

```
scripts/sync.sh                          # PC -> ~/dev/frametop on the Frame
scripts/frame.sh --host -C <dir> '<cmd>' # runs on the SteamOS host (builds too)
scripts/frame.sh -C <dir> '<cmd>'        # runs in the "dev" Fedora distrobox
```

- From a PC, edit only on the PC. The Frame's copy is a mirror that `sync.sh` overwrites.
- Build on the SteamOS host, with the gcc, meson and library headers its image ships; the programs run there too. The root is read-only, so what the host lacks is built into the repo's `build/` folders as static libraries (ft-screens' wlroots, hand tracking's ncnn). CI builds the same `build.sh` scripts in `pack/Containerfile`, whose glibc is the host's version, and every build checks its newest glibc symbol against the host's (`scripts/host-glibc.sh`). [pack/host-and-flatpak.md](pack/host-and-flatpak.md) is the rationale.
- Python that needs more than the host's `python3` (the settings apps' PySide6 and Kirigami, the Hand Recorder, ft-eyes' numpy and OpenCV) runs in Frametop's Python runtime, a Flatpak on KDE's runtime (`pack/flatpak/`), through `scripts/ft-python`, which mounts the repo into it. The Flatpak holds no Frametop code: edit a `.py` file and run it. A new dependency goes in `pyproject.toml` and `uv.lock` (`uv lock`), from which `pack/flatpak/modules.py` generates the wheel list with its sha256s; `pack/flatpak/install.sh` rebuilds the Flatpak when the lock changes. Everything else in Python runs on `/usr/bin/python3`.
- The `dev` container (`setup/dev-container.sh`) is only for Remote Access (Fedora's krdp, FreeRDP, TigerVNC). Its packages go in that script's list, so it can be rebuilt; Fedora packages that need holding at a version, or a patch, go in `setup/container-pins.sh` (krdp and kpipewire are there now; `setup/README.md` says why), never into the container by hand.
- Build output goes in `build/` next to the sources. It's gitignored and never synced.

## The headset may be in use

A Steam Frame is someone's personal headset, and they may be wearing it while you work.

- Don't kill or restart `gamescope`, `steam`, `vrserver`, `vrcompositor`, the gamescope session, or the Frametop desktop without asking. Each one ends or disrupts whatever is happening in VR.
- Don't run host `sudo`, `steamos-readonly disable`, `steamos-devmode` changes, pacman installs, or reboots without explicit approval. Three installers need host `sudo`, and they ask for it: the Bluetooth fixes (`setup/bluetooth/install.sh`), hand tracking (`hands/run.sh install` and `caps`, which set ft-camd's file capabilities with `setcap`, and `uninstall` and `uncaps`, which take them back), and our own eye tracker's frame grabber (`gaze/tracker/install.sh`).
- Write only inside the repo, `/tmp`, and the container unless told otherwise. The installers are the exception: they write the user services, launchers, and the SteamVR driver into the home folder. The Bluetooth fixes and the eye tracker's frame grabber also install root-owned files and system services under `/etc` (`/etc/steamframe`, `/etc/frametop`, `/etc/systemd/system`). When an installer starts writing something new outside the repo, or sets file capabilities, add it to `uninstall.sh` too: users uninstall with that script, not with each installer's `uninstall`.
- Never copy `.netrc`, SSH keys, or Steam config off the Frame or into this repo.

## SteamOS updates

A SteamOS update replaces SteamVR, KWin, and gamescope with the rest of the OS image. When a change starts depending on something from the image (a host file, an OpenVR interface outside the bundled header, an undocumented layout or output format, a SteamVR or KWin quirk), add a check for it to `scripts/update-check.py`, or a retest hint for its package there. [docs/design.md](docs/design.md) has the background.

## The image (`pack/`)

`pack/Containerfile` builds Frametop as an OCI image, the groundwork for installing without building on the headset; no installer uses it yet. [pack/design.md](pack/design.md) explains why and what is open, and [pack/README.md](pack/README.md) documents the specifics. Rules:

- **Pin every input.** Base images by digest, Python via `uv.lock` (commit the lock, never a bare `uv pip install`), downloads by tag or commit and sha256, CI actions by commit SHA.
- **One build recipe.** The image runs the components' own `build.sh` scripts (`FRAME_IN_BOX=1`), and the OpenVR SDK they build against is pinned in `scripts/openvr.sh`. Change a build there, not in the Containerfile, and keep the Containerfile buildable on arm64, the only architecture the Frame has.
- **Keep the tests green in the image.** `./ft dev test` runs `just test` inside it, and CI runs the same recipes. A new offline test that needs no headset goes in the `justfile` too.

## Names

User-facing names are "Frametop", "Frametop Display Settings", and "Frametop Input Settings". Programs and files use the `ft-` / `ft_` prefix (`ft-screens`, `ft-pointer`, `ft-layout`, the `ft_pointer` driver); config, units, and overlay keys use `frametop`. Program names must stay within 15 characters: Linux truncates process names there, and the scripts find programs with `pgrep -x` / `pkill -x`.
