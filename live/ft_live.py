#!/usr/bin/env python3
"""ft-live: a live view of the Frametop desktop's arrangement, in a browser.

It serves one page (ft-live.html) that redraws itself ten times a second from /state.json:
the screens and floating panels where they are in the room, from above and from the front,
the windows on each panel, and the pointer. The state comes from three places:
  - ft-screens' control socket (@ft_screens): the panels' poses, sizes, and which are shown
    ("head", "screens", "toplevels", "get", "concealed");
  - a KWin script, frametop-live.js, loaded into the desktop's KWin over D-Bus like
    ft-floatd's, which sends the outputs, the windows on them, the active window, and KWin's
    pointer (org.frametop.Live.Snapshot) whenever they change. It's unloaded on exit;
  - ft-floatd (@frametop_float, "list"): which window floats on which spare output.

Runs on the host, with its python3 (dbus-python and PyGObject, like ft-floatd). From a
terminal in the Frametop desktop it uses that session's D-Bus; from anywhere else (SSH) it
borrows the session's environment from ft-floatd. The page is on http://127.0.0.1:7780/
by default: from a PC, ssh -L 7780:127.0.0.1:7780 steamos@frame.local, or --bind 0.0.0.0.

Usage: ft-live [--port N] [--bind ADDR] [--once] [--control NAME] [--float NAME]
  --once   print the state as JSON once and exit (no server)
"""
import argparse
import http.server
import json
import math
import os
import re
import signal
import socket
import sys
import threading
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = "frametop-live"
SERVICE, PATH, IFACE = "org.frametop.Live", "/Live", "org.frametop.Live"
PAGE = os.path.join(HERE, "ft-live.html")
TITLE = re.compile(r"KDE Wayland Compositor (WL-\d+)(- Output disabled)?$")


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


# ------------------------------------------------------------------ the session's environment

def session_env():
    """The Frametop session's D-Bus and Wayland, from a process inside it, when this one runs
    outside (over SSH). ft-floatd runs in every Frametop desktop with floating on (a python3
    process, so it's known by its command line); plasmashell is the fallback. Either is told
    from Desktop Mode's by the session's runtime dir."""
    if os.environ.get("XDG_RUNTIME_DIR", "").endswith("/frametop") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return
    want = f"/run/user/{os.getuid()}/frametop"
    keys = ("DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "DISPLAY")
    for pid in sorted(p for p in os.listdir("/proc") if p.isdigit()):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
            if not (len(argv) > 1 and argv[1].endswith(b"/ft_floatd.py")) and argv[0] != b"plasmashell":
                continue
            with open(f"/proc/{pid}/environ", "rb") as f:
                env = dict(e.split("=", 1) for e in f.read().decode(errors="replace").split("\0") if "=" in e)
        except OSError:
            continue
        if env.get("XDG_RUNTIME_DIR") != want or not env.get("DBUS_SESSION_BUS_ADDRESS"):
            continue
        for k in keys:
            if k in env:
                os.environ[k] = env[k]
        return
    sys.exit("ft-live: no Frametop desktop found (no ft-floatd or plasmashell in its session)")


# ------------------------------------------------------------------ ft-screens and ft-floatd

def ask(name, text, timeout=1.0):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        s.bind("")
        s.settimeout(timeout)
        s.sendto(text.encode(), "\0" + name)
        return s.recv(65536).decode(errors="replace")
    except OSError as e:
        return f"error {e}"
    finally:
        s.close()


def floats(name):
    """Spare output -> the id of the window floating on it (ft-floatd's "list")."""
    out = {}
    reply = ask(name, "list")
    if reply.startswith("ok"):
        for part in reply.split()[1:]:
            output, _, wid = part.partition(":")
            if wid and wid != "-":
                out[output] = wid
    return out


def panels(control):
    """Every KWin output's panel: its number, output, size in pixels, whether KWin draws it
    (enabled), and for those, its pose in the room (standing universe) and size in metres."""
    out, count = [], 0
    reply = ask(control, "screens")
    if reply.startswith("ok"):
        count = int(reply.split()[1])
    concealed = set()
    reply = ask(control, "concealed")
    if reply.startswith("ok"):
        concealed = {int(n) for n in reply.split()[1:]}
    reply = ask(control, "toplevels")
    if not reply.startswith("ok"):
        return out, count
    for line in reply.splitlines()[1:]:
        f = line.split(None, 3)
        if len(f) < 4:
            continue
        m = TITLE.search(f[3])
        if not m:
            continue
        n, size = int(f[0]), f[1].split("x")
        p = {"n": n, "output": m.group(1), "kind": "screen" if n <= count else "float",
             "pixels": [int(size[0]), int(size[1])], "enabled": m.group(2) is None, "hidden": n in concealed}
        if p["enabled"]:
            g = ask(control, f"get {n}").split()
            if g and g[0] == "ok" and len(g) >= 17:
                v = [float(x) for x in g[1:13]]
                p.update({"centre": v[0:3], "xaxis": v[3:6], "yaxis": v[6:9], "zaxis": v[9:12],
                          "metres": float(g[13]), "height": float(g[14]), "curve": float(g[15]), "pin": g[16]})
        out.append(p)
    return out, count


def head(control):
    g = ask(control, "head").split()
    if g and g[0] == "ok" and len(g) >= 5:
        return {"x": float(g[1]), "y": float(g[2]), "z": float(g[3]), "yaw": float(g[4])}
    return None


# ------------------------------------------------------------------ the state

class Live:
    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.kwin = {}            # the script's last snapshot
        self.kwin_at = 0.0
        self.cache = None         # (time, state) built for the page, at most ten a second
        self.state_lock = threading.Lock()

    def snapshot(self, text):
        try:
            data = json.loads(text)
        except ValueError as e:
            log(f"bad snapshot: {e}")
            return
        with self.lock:
            self.kwin, self.kwin_at = data, time.time()

    def state(self):
        with self.state_lock:
            now = time.time()
            if self.cache and now - self.cache[0] < 0.1:
                return self.cache[1]
            s = self.build()
            self.cache = (now, s)
            return s

    def build(self):
        with self.lock:
            kwin, kwin_at = self.kwin, self.kwin_at
        ps, screens = panels(self.args.control)
        fl = floats(self.args.float)
        by_output = {o["name"]: o for o in kwin.get("outputs", [])}
        for p in ps:
            o = by_output.get(p["output"])
            p["rect"] = o["rect"] if o else None
            p["scale"] = o["scale"] if o else 1.0
            p["window"] = fl.get(p["output"], "")
        # The pointer: KWin's position (logical, global) on the output under it, in pixels.
        cursor = dict(kwin.get("cursor") or {})
        cursor["output"], cursor["panel"], cursor["px"] = "", 0, None
        if "x" in cursor:
            for p in ps:
                r = p["rect"]
                if r and r["x"] <= cursor["x"] < r["x"] + r["w"] and r["y"] <= cursor["y"] < r["y"] + r["h"]:
                    cursor["output"], cursor["panel"] = p["output"], p["n"]
                    cursor["px"] = [(cursor["x"] - r["x"]) * p["scale"], (cursor["y"] - r["y"]) * p["scale"]]
                    break
        return {"time": time.time(), "kwin_age": round(time.time() - kwin_at, 1) if kwin_at else None,
                "head": head(self.args.control), "screens": screens, "panels": ps,
                "windows": kwin.get("windows", []), "active": kwin.get("active", ""), "cursor": cursor}


class Service(dbus.service.Object):
    def __init__(self, bus, live):
        super().__init__(dbus.service.BusName(SERVICE, bus), PATH)
        self.live = live

    @dbus.service.method(IFACE, in_signature="s", out_signature="")
    def Snapshot(self, text):
        self.live.snapshot(text)


def load_script(bus):
    kwin = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
    if kwin.isScriptLoaded(SCRIPT):
        kwin.unloadScript(SCRIPT)
    sid = int(kwin.loadScript(os.path.join(HERE, "frametop-live.js"), SCRIPT, signature="ss"))
    if sid < 0:
        raise RuntimeError("KWin didn't load the script")
    kwin.start()  # runs every loaded script that isn't running (see ft-floatd on why not Script<id>.run)
    return kwin


def unload_script(kwin):
    try:
        if kwin.isScriptLoaded(SCRIPT):
            kwin.unloadScript(SCRIPT)
    except dbus.DBusException as e:
        log(f"couldn't unload the script: {e}")


# ------------------------------------------------------------------ the page

class Handler(http.server.BaseHTTPRequestHandler):
    live = None

    def log_message(self, *_):
        pass

    def send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            try:
                with open(PAGE, "rb") as f:
                    self.send(200, "text/html; charset=utf-8", f.read())
            except OSError:
                self.send(500, "text/plain", b"ft-live.html is missing\n")
        elif path == "/state.json":
            self.send(200, "application/json", json.dumps(self.live.state()).encode())
        else:
            self.send(404, "text/plain", b"not found\n")


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    p = argparse.ArgumentParser(description="A live view of the Frametop desktop's arrangement")
    p.add_argument("--port", type=int, default=7780)
    p.add_argument("--bind", default="127.0.0.1")
    p.add_argument("--once", action="store_true", help="print the state once as JSON and exit")
    p.add_argument("--control", default="ft_screens", help="ft-screens' control socket")
    p.add_argument("--float", default="frametop_float", help="ft-floatd's socket")
    args = p.parse_args()

    session_env()
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    live = Live(args)
    service = Service(bus, live)  # noqa: F841 (keeps the name)
    kwin = load_script(bus)
    loop = GLib.MainLoop()

    def quit_(*_):
        loop.quit()
        return False

    if args.once:
        GLib.timeout_add(1500, quit_)  # the script's first snapshot comes within its first tick
        loop.run()
        unload_script(kwin)
        json.dump(live.state(), sys.stdout, indent=1)
        print()
        return

    Handler.live = live
    server = Server((args.bind, args.port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log(f"live view on http://{args.bind}:{args.port}/")
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, quit_)
    try:
        loop.run()
    finally:
        server.shutdown()
        unload_script(kwin)
        log("script unloaded")


if __name__ == "__main__":
    main()
