#!/usr/bin/env python3
"""Write frametop-release.json, for a release's Frametop.zip (framedrop/build.sh): the version,
the commit, the channel, the tree's and the Flatpak bundle's file names and sha256, the
Flatpak's app id and runtime, and the SteamOS table, pack/steamos.json.
pack/install-release.sh reads it.

  pack/release-info.py --tree-file frametop-tree.tar.zst --flatpak-file frametop.flatpak \\
      --version 0.3.0 --commit SHA [--channel stable|experimental] > frametop-release.json

The tree is the repo at the commit, built (the build image's /src/frametop, as a zstd tar);
the bundle is pack/flatpak/build.sh's. The channel defaults to experimental for a version
with a "-" (0.3.0-exp.1), else stable.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "flatpak" / "io.github.frametop.Frametop.yml"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def flatpak_ids(manifest=MANIFEST):
    """The app id and the runtime (org.kde.Platform//6.11) the manifest names."""
    fields = {}
    for line in manifest.read_text().splitlines():
        m = re.match(r"^(id|runtime|runtime-version):\s*'?([^'#]+?)'?\s*$", line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields["id"], f"{fields['runtime']}//{fields['runtime-version']}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tree-file", required=True, type=Path)
    ap.add_argument("--flatpak-file", required=True, type=Path)
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--channel", choices=("stable", "experimental"))
    ap.add_argument("--steamos", type=Path, default=HERE / "steamos.json")
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    a = ap.parse_args()
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}", a.version):
        ap.error(f"--version is malformed: {a.version!r}")
    if not re.fullmatch(r"[0-9a-f]{7,40}", a.commit):
        ap.error(f"--commit is malformed: {a.commit!r}")
    table = json.loads(a.steamos.read_text())
    app, runtime = flatpak_ids(a.manifest)
    json.dump({
        "schema": "frametop.release/v2",
        "version": a.version,
        "commit": a.commit,
        "channel": a.channel or ("experimental" if "-" in a.version else "stable"),
        "tree": {"file": a.tree_file.name, "sha256": sha256(a.tree_file)},
        "flatpak": {"file": a.flatpak_file.name, "sha256": sha256(a.flatpak_file), "app": app, "runtime": runtime},
        "steamos": {"tested": table.get("tested", []), "broken": table.get("broken", [])},
    }, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
