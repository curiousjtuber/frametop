#!/bin/bash
# Runs on the Frame host. The capture server for remote access: KRdp's krdpserver (from
# the dev container) talks to the nested KWin directly (--plasma, no desktop portal) and
# serves the whole workspace over RDP on every address, port 3390. It's for two clients:
# vnc-bridge.sh on 127.0.0.1, which re-serves the primary screen over VNC, and any RDP
# client on the LAN or the tailnet (krdc, Remmina, Windows Remote Desktop), which gets
# every screen with the cursor as a pointer shape and no extra hop. RDP brings its own
# TLS and NLA login, which is why it may face the LAN where VNC (tailnet only) can't.
# Started by frametop-session.sh when REMOTE=1.
set -eu

runtime=${1:?usage: remote-desktop.sh <nested XDG_RUNTIME_DIR>}
# 3389 is taken by SteamOS's own xrdp (a separate X11 session, not the VR desktop).
port=${RDP_PORT:-3390}
creds=$HOME/.config/frametop-remote

mkdir -p -m 0700 "$creds"
# The RDP password, made once so clients can keep it. krdp takes it only on its command
# line, where other local users could read it; the Frame is one person's headset.
if [ ! -s "$creds/rdp-password" ]; then
  (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=' | cut -c1-20 > "$creds/rdp-password")
fi
if [ ! -s "$creds/cert.pem" ]; then
  (umask 077; openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(hostname)" \
    -keyout "$creds/key.pem" -out "$creds/cert.pem" 2>/dev/null)
fi

# Wait for the nested KWin to come up.
for _ in $(seq 60); do
  [ -S "$runtime/wayland-0" ] && break
  sleep 1
done

# podman needs the real runtime dir. The nested one is passed only to krdpserver.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
exec ~/.local/bin/distrobox enter dev -- env XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
  krdpserver --plasma --address 0.0.0.0 --port "$port" \
  -u "$(id -un)" -p "$(cat "$creds/rdp-password")" \
  --certificate "$creds/cert.pem" --certificate-key "$creds/key.pem"
