#!/usr/bin/env bash
# Create or update the Python environment that runs Frametop Display Settings and Frametop
# Input Settings on the SteamOS host, without the dev container. Safe to re-run: it only
# rebuilds when the host's Qt version has changed (after a SteamOS update) or it's missing.
# Usage: setup/pyside-venv.sh [--force]   (on the Frame, or from a PC over SSH)
# Needs mise in ~/.local/bin on the Frame; Python 3.13 and uv come from it.
#
# The host has Qt 6 and Kirigami (Plasma uses them) but no PySide6. So this installs
# PySide6's bindings from PyPI, pinned to the host's exact Qt version, into
# ~/.local/share/frametop/pyside, and deletes the copy of Qt the wheel brings: the
# bindings load the host's /usr/lib/libQt6*, which the host's Kirigami and Breeze style
# are built against. One mismatch remains, patched by retag-versions.py: SteamOS's Qt
# exports three QML engine functions as Qt_6 where PySide expects Qt_6_PRIVATE_API.
# bin/frametop-python runs the venv's Python with Qt's plugin and QML paths on the host's.
# The settings apps' launchers in install-cross.sh's copy run on it (README-cross.md).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$root/scripts/_env.sh"
"$root/scripts/sync.sh" >/dev/null

on_frame_script "$FRAME_REPO" "${1:-}" <<'EOF'
set -euo pipefail
repo=$1 force=$2
export PATH=$HOME/.local/bin:$PATH
command -v mise >/dev/null || { echo "mise not found in ~/.local/bin (https://mise.jdx.dev)" >&2; exit 1; }
venv=$HOME/.local/share/frametop/pyside
python=3.13  # PySide6 6.8 supports Python up to 3.13
qt=$(pacman -Q qt6-base | awk '{print $2}'); qt=${qt%%-*}  # e.g. 6.8.0
want="qt $qt python $python"

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

if [ "$force" != --force ] && [ "$(cat "$venv/frametop-version" 2>/dev/null)" = "$want" ] && check; then
  echo "up to date: $venv"
  exit 0
fi

uv() { mise exec uv -- uv "$@"; }
mise install -q "python@$python"
py=$(mise where "python@$python")/bin/python$python
echo "building $venv (Python $python, PySide6 for Qt $qt)"
[ -n "${venv#"$HOME"/}" ] && rm -rf "$venv"
uv venv -q -p "$py" "$venv"
# PySide6-Essentials has every module the apps import; PySide6 itself would add 130 MB
# of Addons. A 6.8.0.x release is a PySide fix on Qt 6.8.0, so the newest one wins.
uv pip install -q -p "$venv/bin/python" "PySide6-Essentials==$qt.*"
site=$("$venv/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
rm -rf "$site/PySide6/Qt/lib" "$site/PySide6/Qt/plugins" "$site/PySide6/Qt/qml"
uv run -q --no-project -p "$py" --with pyelftools python "$repo/setup/retag-versions.py" \
  "$(ls "$site"/PySide6/libpyside6qml.abi3.so.*)" libQt6Qml.so.6 /usr/lib/libQt6Qml.so.6 Qt_6_PRIVATE_API Qt_6
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
