"""fthost: commands on the SteamOS host, from Frametop's Python runtime the apps run in (the
Flatpak scripts/ft-python starts; pack/host-and-flatpak.md).

host_command(*cmd) is the argv for one. In the sandbox, flatpak-spawn --host runs it outside,
through the portal on the user's real session bus; the command gets that bus too (ours is the
sandbox's proxy, and inside the desktop the nested session's private one, where systemd-run
fails) and the desktop's Wayland socket, which ft-python hands us as FT_HOST_WAYLAND_DISPLAY
(ours is the sandbox's). It runs from the home folder: the portal starts the command in the
caller's folder, and one only the sandbox has doesn't exist on the host (every command then
exits 127). Run by hand on the host, outside a sandbox, it's the command itself.

recorder/common.py has the same function: the standalone Hand Recorder ships recorder/ without
conf/. Standard library only.
"""

import os


def in_container():
    return os.path.exists("/.flatpak-info") or os.path.exists("/run/.containerenv") or os.path.exists("/.dockerenv")


def host_command(*cmd):
    if not os.path.exists("/.flatpak-info"):
        return list(cmd)
    env = ["-C", os.path.expanduser("~"), f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{os.getuid()}/bus"]
    if os.environ.get("FT_HOST_WAYLAND_DISPLAY"):
        env.append("WAYLAND_DISPLAY=" + os.environ["FT_HOST_WAYLAND_DISPLAY"])
    return ["flatpak-spawn", "--host", "env", *env, *cmd]
