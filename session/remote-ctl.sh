#!/bin/bash
# Start, stop, or ask about remote access to the Frametop desktop: remote-desktop.sh (krdp
# serving every screen over RDP, on the LAN and the tailnet) and vnc-bridge.sh (VNC of its
# primary screen, on the tailnet). Runs on the Frame host; frametop-session.sh and Frametop Remote Access
# (remote/ft-remote-settings) use it.
#
#   remote-ctl.sh start | stop | restart | status
#
# Capture only works in a desktop that started with REMOTE=1: KWin's permission checks for
# screencast and fake input are turned off when it starts, and only then. Such a session
# leaves $runtime/remote-capable; without it, start says so (exit 3) and the setting applies
# at the next desktop start. status prints key=value lines: capable, running, address and
# name (tailnet), port (VNC), rdp_port, lan (the LAN address), host, user.
set -u

here=$(dirname "$(readlink -f "$0")")
runtime=/run/user/$(id -u)/frametop
vnc_port=${VNC_PORT:-5900}
rdp_port=${RDP_PORT:-3390}

running() { pgrep -f '[X]vnc :20 ' >/dev/null && pgrep -f '[k]rdpserver --plasma' >/dev/null; }

stop() {
  pkill -f "[v]nc-bridge.sh" 2>/dev/null
  pkill -f "[r]emote-desktop.sh" 2>/dev/null
  pkill -f '[k]rdpserver --plasma' 2>/dev/null
  pkill -f '[X]vnc :20 ' 2>/dev/null
  pkill -f '[x]freerdp /v:' 2>/dev/null
  return 0
}

start() {
  if [ ! -e "$runtime/remote-capable" ]; then
    echo "this desktop didn't start with remote access on: it applies at the next desktop start" >&2
    return 3
  fi
  running && return 0
  stop
  setsid "$here/remote-desktop.sh" "$runtime" > /tmp/frametop-remote.log 2>&1 < /dev/null &
  setsid "$here/vnc-bridge.sh" > /tmp/frametop-vnc.log 2>&1 < /dev/null &
  return 0
}

case ${1:-status} in
  start) start ;;
  stop) stop ;;
  restart) stop; sleep 1; start ;;
  status)
    addr=$(ip -4 -o addr show tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    name=$(curl -s --max-time 2 --unix-socket /run/tailscale/tailscaled.sock \
             http://local-tailscaled.sock/localapi/v0/status 2>/dev/null |
           python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null)
    echo "capable=$([ -e "$runtime/remote-capable" ] && echo 1 || echo 0)"
    echo "running=$(running && echo 1 || echo 0)"
    echo "address=$addr"
    echo "name=$name"
    echo "port=$vnc_port"
    echo "rdp_port=$rdp_port"
    echo "lan=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
    echo "host=$(hostname)"
    echo "user=$(id -un)" ;;
  *) echo "usage: $0 start|stop|restart|status" >&2; exit 2 ;;
esac
