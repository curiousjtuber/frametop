#!/usr/bin/env python3
"""Offline test of install-release.sh's install, release after release (docs/charts G7): which
release is "current", which folders stay, and a reinstall over fast-installed files. Each
release is a made-up tree in a real frametop-tree.tar.zst with a made-up bundle, /etc/os-release
a made-up one, and each tree's install.sh is install.sh's own "current" block. Everything
happens in a temp folder: no flatpak, no install, no network.

  pack/test/install-release-test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
TMP = tempfile.mkdtemp(prefix="ft-install-release-test-")
RELEASES = os.path.join(TMP, "releases")
OS_RELEASE = os.path.join(TMP, "os-release")
Path(OS_RELEASE).write_text('ID=steamos\nVARIANT_ID=vr\nBUILD_ID=20260922.6101926\nVERSION_ID=3.8\n')
SCRIPT = (Path(REPO, "pack", "install-release.sh").read_text().rsplit('\nmain "$@"', 1)[0]
          .replace("/etc/os-release", OS_RELEASE))

# install.sh's block that makes its own release current, as each made-up tree's install.sh
INSTALL = Path(REPO, "install.sh").read_text()
start = INSTALL.index("# A release's install.sh is also how you go back to it")
CURRENT_BLOCK = INSTALL[start:INSTALL.index('step "Done"', start)]

failures = []


def check(label, got, want):
    ok = got == want
    print(("ok    " if ok else "FAIL  ") + label + ("" if ok else f": got {got!r}, want {want!r}"), flush=True)
    if not ok:
        failures.append(label)


def make_zip(version):
    """An unpacked Frametop.zip for VERSION: its tree (one install.sh) as the tar, and a bundle."""
    unpacked = os.path.join(TMP, f"zip-{version}")
    tree = os.path.join(TMP, f"tree-{version}")
    os.makedirs(unpacked)
    os.makedirs(tree)
    Path(tree, "install.sh").write_text('#!/usr/bin/env bash\nset -euo pipefail\nroot=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)\n'
                                        'FRAME_RELEASE=1 FRAME_LOCAL=1\necho "install.sh of $root"\n' + CURRENT_BLOCK)
    os.chmod(os.path.join(tree, "install.sh"), 0o755)
    tar = os.path.join(unpacked, "frametop-tree.tar.zst")
    subprocess.run(["tar", "--zstd", "-C", tree, "-cf", tar, "."], check=True)
    bundle = os.path.join(unpacked, "frametop.flatpak")
    Path(bundle).write_bytes(b"not a bundle: " + version.encode())
    table = os.path.join(TMP, "steamos.json")
    Path(table).write_text(json.dumps({"tested": [{"build": "20260922.6101926", "version": version}]}))
    out = subprocess.run([sys.executable, os.path.join(REPO, "pack", "release-info.py"), "--tree-file", tar,
                          "--flatpak-file", bundle, "--version", version, "--commit", "1234567", "--steamos", table],
                         capture_output=True, text=True, check=True).stdout
    Path(unpacked, "frametop-release.json").write_text(out)
    return unpacked


ZIPS = {v: make_zip(v) for v in ("1.0", "2.0", "3.0")}


def install(version):
    unpacked = ZIPS[version]
    env = dict(os.environ, FRAMETOP_STEAMOS_TABLE="none")
    r = subprocess.run(["bash", "-c", SCRIPT + 'main "$@"', "install-release.sh", "--yes", "--dir", RELEASES],
                       cwd=unpacked, env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, check=False)
    return r.returncode, r.stdout + r.stderr


def current():
    link = os.path.join(RELEASES, "current")
    return os.readlink(link) if os.path.islink(link) else None


def folders():
    return sorted(d for d in os.listdir(RELEASES) if d != "current")


code, out = install("1.0")
check("the first release installs", (code, current(), folders()), (0, "1.0", ["1.0"]))
check("its bundle is in the tree, for install.sh", os.path.isfile(os.path.join(RELEASES, "1.0", "pack/flatpak/build/frametop.flatpak")), True)
check("and .frametop-release names the version, the app and the tree's sha256",
      sorted(line.split("=")[0] for line in Path(RELEASES, "1.0", ".frametop-release").read_text().splitlines()),
      ["CHANNEL", "COMMIT", "FLATPAK", "FLATPAK_SHA256", "TREE_SHA256", "VERSION"])
code, out = install("2.0")
check("the next one is current, and the one before stays", (code, current(), folders()), (0, "2.0", ["1.0", "2.0"]))
code, out = install("3.0")
check("two releases on, the oldest goes; the one current before stays, though install.sh "
      "moved current first", (code, current(), folders()), (0, "3.0", ["2.0", "3.0"]))

# Going back: the older release's install.sh makes it current, so fast-install and get.sh follow.
r = subprocess.run([os.path.join(RELEASES, "2.0", "install.sh")], capture_output=True, text=True, check=False)
check("running the release before's install.sh makes it current", (r.returncode, current()), (0, "2.0"))
r = subprocess.run(["bash", os.path.join(RELEASES, "current", "install.sh")], capture_output=True, text=True,
                   check=False)
check("...also through the current link", (r.returncode, current()), (0, "2.0"))
code, out = install("3.0")
check("installing 3.0 again makes it current, and 2.0 stays", (code, current(), folders()), (0, "3.0", ["2.0", "3.0"]))

# A reinstall over fast-installed files is refused, and nothing changes.
os.makedirs(os.path.join(RELEASES, "3.0", ".fast-install"))
Path(RELEASES, "3.0", ".fast-install", "state.json").write_text("{}")
code, out = install("3.0")
check("a reinstall over fast-installed files is refused", (code, "fast-install undo" in out), (1, True))
check("and current and the folders stay", (current(), folders()), ("3.0", ["2.0", "3.0"]))

# A damaged tree stops before anything is unpacked, with status 3 (get.sh downloads again).
shutil.rmtree(RELEASES)
damaged = ZIPS["1.0"]
Path(damaged, "frametop-tree.tar.zst").write_bytes(b"bit rot")
code, out = install("1.0")
check("a damaged tree is refused with status 3", (code, "damaged" in out, os.path.exists(RELEASES)), (3, True, False))

shutil.rmtree(TMP)
print("FAILED: " + ", ".join(failures) if failures else "all passed", flush=True)
sys.exit(1 if failures else 0)
