#!/usr/bin/env python3
"""Offline test of a release's SteamOS check and its frametop-release.json: install-release.sh's
check_release (the script without its last line, which would install), on files
pack/release-info.py writes from small made-up tree and bundle files. No network, flatpak, or
install.

  pack/test/release-test.py
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
TMP = tempfile.mkdtemp(prefix="ft-release-test-")
SCRIPT = Path(REPO, "pack", "install-release.sh").read_text().rsplit('\nmain "$@"', 1)[0]

OURS = "20260922.6101926"   # tested
NEW = "20261007.6180005"    # in no table
failures = []


def check(label, got, want):
    ok = got == want
    print(("ok    " if ok else "FAIL  ") + label + ("" if ok else f": got {got!r}, want {want!r}"), flush=True)
    if not ok:
        failures.append(label)


def write(name, obj):
    path = os.path.join(TMP, name)
    with open(path, "w") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))
    return path


def info(version, steamos, *extra):
    table = write("steamos.json", steamos)
    r = subprocess.run([sys.executable, os.path.join(REPO, "pack", "release-info.py"), "--tree-file", TREE,
                        "--flatpak-file", BUNDLE, "--version", version, "--commit", "1234567", "--steamos", table,
                        *extra], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"release-info.py failed: {r.stderr}")
    return json.loads(r.stdout)


def check_release(release, table, build):
    """check_release's lines, or the error line with status 'error'."""
    rel = write("frametop-release.json", release)
    tab = write("table.json", table) if table is not None else ""
    r = subprocess.run(["bash", "-c", SCRIPT + f'\ncheck_release "$@"', "--", rel, tab, build],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return ["error", r.stderr.strip()]
    return r.stdout.rstrip("\n").split("\n")


TREE = os.path.join(TMP, "frametop-tree.tar.zst")
BUNDLE = os.path.join(TMP, "frametop.flatpak")
Path(TREE).write_bytes(b"not really a tar, but a file with a sha256\n")
Path(BUNDLE).write_bytes(b"not really a bundle\n")
TREE_SHA = hashlib.sha256(Path(TREE).read_bytes()).hexdigest()
BUNDLE_SHA = hashlib.sha256(Path(BUNDLE).read_bytes()).hexdigest()
TESTED = {"tested": [{"build": OURS, "version": "0.4.5"}], "broken": []}

# --- release-info.py
rel = info("0.3.0", TESTED)
check("release-info.py writes the v2 schema", rel["schema"], "frametop.release/v2")
check("with both files' sha256", (rel["tree"]["sha256"], rel["flatpak"]["sha256"]), (TREE_SHA, BUNDLE_SHA))
check("and the file names", (rel["tree"]["file"], rel["flatpak"]["file"]), ("frametop-tree.tar.zst", "frametop.flatpak"))
check("and the Flatpak's app and runtime from the manifest",
      (rel["flatpak"]["app"], rel["flatpak"]["runtime"].split("//")[0]), ("io.github.frametop.Frametop", "org.kde.Platform"))
check("stable for a plain version", rel["channel"], "stable")
check("experimental for a prerelease", info("0.3.0-exp.1", TESTED)["channel"], "experimental")
check("--channel wins", info("0.3.0-exp.1", TESTED, "--channel", "stable")["channel"], "stable")
check("the SteamOS table comes along", rel["steamos"]["tested"][0]["build"], OURS)

# --- check_release: the SteamOS table
out = check_release(rel, None, OURS)
check("tested on this build, from the release's own table", out[0], "tested")
check("and the sha256s, the app and the version come through", (out[1], out[4], out[5], out[6]),
      ("0.3.0", TREE_SHA, BUNDLE_SHA, "io.github.frametop.Frametop"))
out = check_release(rel, None, NEW)
check("untested on a build in no table", out[0], "untested")
check("names what it was tested on", "0.4.5" in out[7] and OURS in out[7], True)
newer = {"tested": [{"build": OURS, "version": "0.4.5"}, {"build": NEW, "version": "0.4.6"}], "broken": []}
check("Frametop's newer table counts when it was fetched", check_release(rel, newer, NEW)[0], "tested")
check("a fetched table that isn't one is ignored", check_release(rel, {"nope": 1}, OURS)[0], "tested")

broken = {"tested": [], "broken": [{"build": NEW, "reason": "KWin 6.3 moved the outputs", "from": "0.3.0", "fixed_in": "0.3.2"}]}
out = check_release(rel, broken, NEW)
check("broken on a build the table marks", out[0], "broken")
check("with the reason and the fix", "KWin 6.3" in out[7] and "0.3.2" in out[7], True)
check("a release before 'from' isn't broken by it", check_release(info("0.2.9", TESTED), broken, NEW)[0], "untested")
check("nor one from 'fixed_in' on", check_release(info("0.3.2", TESTED), broken, NEW)[0], "untested")
check("an experimental release counts as the release it leads to",
      check_release(info("0.3.1-exp.2", TESTED), broken, NEW)[0], "broken")

# --- check_release: a release that isn't usable
for label, bad in (("an older schema", {"schema": "frametop.release/v1"}),
                   ("a version that isn't one", {"version": "../x"}),
                   ("a tree sha256 that isn't one", {"tree": {"file": "frametop-tree.tar.zst", "sha256": "latest"}}),
                   ("no flatpak app", {"flatpak": {"file": "frametop.flatpak", "sha256": BUNDLE_SHA}}),
                   ("a flatpak app that isn't an id", {"flatpak": {"file": "frametop.flatpak", "sha256": BUNDLE_SHA, "app": "rm -rf"}})):
    r = dict(rel, **bad)
    check(f"refuses {label}", check_release(r, None, OURS)[0], "error")
check("refuses a file that isn't JSON", check_release("{", None, OURS)[0], "error")

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all ok")
