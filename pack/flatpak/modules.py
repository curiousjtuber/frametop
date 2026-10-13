#!/usr/bin/env python3
"""The Python packages of Frametop's Flatpak, as a flatpak-builder module, from uv.lock.

    pack/flatpak/modules.py [--out FILE] [--list]

The Flatpak (io.github.frametop.Frametop.yml) is the Python runtime for the apps that need
more than the host's python3: the settings apps' PySide6 and the trackers' numpy and OpenCV
(pack/host-and-flatpak.md), and pytest, for the suites that need KDE. uv.lock pins them, with
every wheel's sha256, so the module this writes is the lock's apps and tracker groups (and
pytest from dev), closed over their dependencies for the runtime
(Python 3.13 on aarch64 Linux), each as the one wheel pip will install there, fetched by
flatpak-builder and checked. pyproject.toml and `uv lock` are the only places versions change.
--list prints the packages and wheels instead.
"""
import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = HERE.parent.parent / "uv.lock"
GROUPS = ("apps", "tracker")
# From the dev group, the test runner alone: the suites that need KDE (kwriteconfig6, PySide6)
# run in the Flatpak, in CI and by hand (release.yml), not in the build image.
DEV_PACKAGES = ("pytest",)
# What the KDE 6.11 runtime is (pack/flatpak/io.github.frametop.Frametop.yml): the markers in
# the lock are evaluated for it, and the wheels chosen for it.
PYTHON = "3.13"
PYTHON_FULL = "3.13.15"
ABI_TAGS = ("cp313", "abi3", "none")
PLATFORM_RE = re.compile(r"^(manylinux(2014|_2_\d+)_aarch64(\.manylinux_2_\d+_aarch64)*|linux_aarch64|any)$")


class V(str):
    """A value in a marker: two versions compare numerically (as PEP 440 orders the simple
    ones), anything else as the strings they are."""
    @staticmethod
    def _keys(a, b):
        if re.fullmatch(r"\d+(\.\d+)*", a) and re.fullmatch(r"\d+(\.\d+)*", b):
            return tuple(int(p) for p in a.split(".")), tuple(int(p) for p in b.split("."))
        return str(a), str(b)

    def __lt__(self, o): a, b = self._keys(self, o); return a < b
    def __le__(self, o): a, b = self._keys(self, o); return a <= b
    def __gt__(self, o): a, b = self._keys(self, o); return a > b
    def __ge__(self, o): a, b = self._keys(self, o); return a >= b
    def __eq__(self, o): a, b = self._keys(self, o); return a == b
    def __ne__(self, o): return not self == o
    __hash__ = str.__hash__


MARKER_ENV = {
    "sys_platform": "linux", "platform_system": "Linux", "os_name": "posix",
    "platform_machine": "aarch64", "platform_python_implementation": "CPython",
    "implementation_name": "cpython", "python_version": V(PYTHON), "python_full_version": V(PYTHON_FULL),
    "implementation_version": V(PYTHON_FULL), "extra": "",
}


def marker_true(marker):
    """A PEP 508 marker, for the runtime. The lock's markers are plain comparisons joined by
    and/or, which are Python expressions once the version strings compare numerically."""
    if not marker:
        return True
    expr = re.sub(r"'([^']*)'", lambda m: f"V({m.group(1)!r})", marker)
    return bool(eval(expr, {"__builtins__": {}, "V": V}, MARKER_ENV))  # noqa: S307


def wheel_for(pkg):
    """The lock's one wheel for the runtime, or None: a tag the runtime's pip accepts, with
    the newest manylinux it allows preferred (the runtime's glibc is newer than any of them)."""
    best = None
    for w in pkg.get("wheels", []):
        name = w["url"].rsplit("/", 1)[-1]
        m = re.match(r"^(?P<dist>[^-]+)-(?P<ver>[^-]+)(-(?P<build>\d[^-]*))?-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+)\.whl$", name)
        if not m:
            continue
        pys = m.group("py").split(".")
        ok_py = any(p in ("py3", f"cp{PYTHON.replace('.', '')}") or re.fullmatch(r"py3\d*", p) or
                    (p.startswith("cp3") and p[2:].isdigit() and int(p[2:]) <= int(PYTHON.replace(".", "")) and
                     m.group("abi") == "abi3") for p in pys)
        if not ok_py or m.group("abi") not in ABI_TAGS or not PLATFORM_RE.match(m.group("plat")):
            continue
        rank = (0 if m.group("plat") == "any" else max(int(x) for x in re.findall(r"_2_(\d+)", m.group("plat")) or [17]),
                m.group("abi") == f"cp{PYTHON.replace('.', '')}")
        if best is None or rank > best[0]:
            best = (rank, name, w)
    return best and (best[1], best[2])


def closure(lock):
    pkgs = {p["name"]: p for p in lock["package"]}
    root = next(p for p in lock["package"] if p["name"] == "frametop")
    want, todo = {}, []
    for group in GROUPS:
        for dep in root.get("dev-dependencies", {}).get(group, []):
            todo.append(dep)
    for dep in root.get("dev-dependencies", {}).get("dev", []):
        if dep["name"] in DEV_PACKAGES:
            todo.append(dep)
    while todo:
        dep = todo.pop()
        if not marker_true(dep.get("marker")):
            continue
        name = dep["name"]
        if name in want:
            continue
        want[name] = pkgs[name]
        todo.extend(pkgs[name].get("dependencies", []))
        for extra in dep.get("extra", []):
            todo.extend(pkgs[name].get("optional-dependencies", {}).get(extra, []))
    return dict(sorted(want.items()))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1])
    ap.add_argument("--out", type=Path, help="write the module here (default: stdout)")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    with open(LOCK, "rb") as f:
        lock = tomllib.load(f)
    want = closure(lock)
    sources, names, missing = [], [], []
    for name, pkg in want.items():
        found = wheel_for(pkg)
        if not found:
            missing.append(f"{name} {pkg['version']}")
            continue
        fname, w = found
        sources.append({"type": "file", "url": w["url"], "sha256": w["hash"].removeprefix("sha256:"),
                        "dest-filename": fname})
        names.append(f"{name}=={pkg['version']}")
        if a.list:
            print(f"{name} {pkg['version']}  {fname}")
    if missing:
        sys.exit("no wheel for the runtime (Python %s, aarch64) in uv.lock: %s" % (PYTHON, ", ".join(missing)))
    if a.list:
        return
    site = "${FLATPAK_DEST}/lib/python3.%s/site-packages" % PYTHON.split(".")[1]
    module = {
        "name": "python-packages",
        "buildsystem": "simple",
        # The runtime's pip, offline, from the wheels fetched above; --no-build-isolation and
        # --no-deps keep it to exactly the lock's set. PySide6's wheel brings a Qt of its own,
        # the same version as the runtime's; the bindings run on the runtime's instead (its
        # plugins and QML, Kirigami among them, were built against it, and a Kirigami window
        # loaded into the wheel's copy hung in its QML thread), so the wheel's copy goes, and
        # the loader finds the runtime's by soname.
        "build-commands": [
            "pip3 install --verbose --no-index --no-deps --no-build-isolation --find-links=\"file://${PWD}\" "
            "--prefix=${FLATPAK_DEST} " + " ".join(names),
            "rm -rf %s/PySide6/Qt" % site,
            "%s -c 'import PySide6.QtCore, numpy, cv2'" % "python3",
        ],
        "sources": sources,
    }
    text = json.dumps(module, indent=2) + "\n"
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(text)
        print(f"wrote {a.out}: {len(names)} packages")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
