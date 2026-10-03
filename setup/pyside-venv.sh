#!/usr/bin/env bash
# Create or update the Python environment that runs Frametop Display Settings and Frametop
# Input Settings on the SteamOS host, in build/pyside. Safe to re-run: it only rebuilds when
# the host's Qt or Python version has changed (after a SteamOS update) or it's missing.
# Usage: setup/pyside-venv.sh [--force]   (on the Frame, or from a PC over SSH)
#
# The host has Qt 6 and Kirigami (Plasma uses them) but no PySide6. So this installs
# PySide6's bindings from PyPI into a venv of the host's own Python, pinned to the host's
# exact Qt version, and deletes the copy of Qt the wheel brings: the bindings load the host's
# /usr/lib/libQt6*, which the host's Kirigami and Breeze style are built against. One
# mismatch remains, patched below: SteamOS's Qt exports a few QML engine functions as Qt_6
# where PySide expects Qt_6_PRIVATE_API. bin/frametop-python runs the venv's Python with
# Qt's plugin and QML paths on the host's; the settings apps' launchers use it.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$root/scripts/_env.sh"
"$root/scripts/sync.sh" >/dev/null

on_frame_script "$FRAME_REPO" "${1:-}" <<'EOF'
set -euo pipefail
repo=$1 force=$2
venv=$repo/build/pyside
# The host's own Python, not whatever a shell on the Frame puts first (mise, pyenv): PySide6
# for the host's Qt has wheels for its version.
py=/usr/bin/python3
qt=$(pacman -Q qt6-base | awk '{print $2}'); qt=${qt%%-*}  # e.g. 6.8.0
want="qt $qt $($py --version)"

check() {  # the apps' imports, on the host's Qt, without a display
  QT_QPA_PLATFORM=offscreen "$venv/bin/frametop-python" -c '
from PySide6.QtCore import qVersion
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
import PySide6
QGuiApplication([])
libs = {l.split()[-1].rsplit("/", 1)[0] for l in open("/proc/self/maps") if "libQt6" in l}
assert libs == {"/usr/lib"}, libs
print(f"PySide6 {PySide6.__version__} on the host Qt {qVersion()}")'
}

if [ "$force" != --force ] && [ "$(cat "$venv/frametop-version" 2>/dev/null)" = "$want" ] && check 2>/dev/null; then
  echo "up to date: $venv"
  exit 0
fi

echo "building $venv ($($py --version), PySide6 for Qt $qt)"
rm -rf "$venv"
$py -m venv "$venv"
pip() { "$venv/bin/python" -m pip -q --disable-pip-version-check "$@"; }
# PySide6-Essentials has every module the apps import; PySide6 itself would add 130 MB of
# Addons. A 6.8.0.x release is a PySide fix on Qt 6.8.0, so the newest one wins.
pip install "PySide6-Essentials==$qt.*" pyelftools
site=$("$venv/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
rm -rf "$site/PySide6/Qt/lib" "$site/PySide6/Qt/plugins" "$site/PySide6/Qt/qml"

# Retag libpyside6qml's imports from libQt6Qml: each Qt_6_PRIVATE_API one the host's Qt
# exports only as Qt_6 gets Qt_6. Same functions, same signatures, but the loader matches
# the version tag too. This rewrites each import's index in .gnu.version.
"$venv/bin/python" - "$(ls "$site"/PySide6/libpyside6qml.abi3.so.*)" libQt6Qml.so.6 /usr/lib/libQt6Qml.so.6 \
  Qt_6_PRIVATE_API Qt_6 <<'PY'
import sys
from elftools.elf.elffile import ELFFile

lib, soname, provider, old, new = sys.argv[1:]

def exported(path):  # {(name, version)} of a library's defined dynamic symbols
    with open(path, "rb") as f:
        elf = ELFFile(f)
        dynsym, versym = elf.get_section_by_name(".dynsym"), elf.get_section_by_name(".gnu.version")
        names = {0: None, 1: None}
        for vd, auxs in elf.get_section_by_name(".gnu.version_d").iter_versions():
            names[vd["vd_ndx"]] = next(auxs).name
        return {(s.name, names.get(versym.get_symbol(i)["ndx"] & 0x7FFF))
                for i, s in enumerate(dynsym.iter_symbols()) if s["st_shndx"] != "SHN_UNDEF"}

have = exported(provider)
with open(lib, "rb") as f:
    elf = ELFFile(f)
    dynsym, versym = elf.get_section_by_name(".dynsym"), elf.get_section_by_name(".gnu.version")
    index = {}
    for vn, auxs in elf.get_section_by_name(".gnu.version_r").iter_versions():
        if vn.name == soname:
            index = {a.name: a["vna_other"] for a in auxs}
    patches = []
    if old in index and new in index:
        for i, s in enumerate(dynsym.iter_symbols()):
            if s["st_shndx"] == "SHN_UNDEF" and versym.get_symbol(i)["ndx"] == index[old] \
                    and (s.name, old) not in have and (s.name, new) in have:
                patches.append((versym["sh_offset"] + 2 * i, s.name))
with open(lib, "r+b") as f:
    for offset, name in patches:
        f.seek(offset)
        f.write(index[new].to_bytes(2, "little" if elf.little_endian else "big"))
print(f"retagged {len(patches)} imports {old} -> {new}")
PY

# PySide points Qt at the wheel's own Qt folder (a built-in qt.conf), now gone.
cat > "$venv/bin/frametop-python" <<'WRAP'
#!/bin/sh
export QT_PLUGIN_PATH=/usr/lib/qt6/plugins QML_IMPORT_PATH=/usr/lib/qt6/qml
exec "$(dirname "$0")/python" "$@"
WRAP
chmod +x "$venv/bin/frametop-python"
check
echo "$want" > "$venv/frametop-version"
EOF
