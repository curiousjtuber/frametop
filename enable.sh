#!/usr/bin/env bash
# Turn Frametop off without uninstalling it, and back on. On the Frame or from a PC.
# Usage: ./enable.sh              # turn it back on (what disable.sh turned off)
#        ./enable.sh off [--now]  # the same as ./disable.sh [--now]
#        ./enable.sh status
#
# off: Frametop's services no longer start with SteamVR, the 3D mouse's driver is unregistered
# from SteamVR, and its launcher entries (Frametop and its profiles) go. The code, the settings,
# the settings apps' menu entries, and the system files (the Bluetooth fixes, our eye tracker's
# frame grabber) stay. What runs now keeps running until SteamVR restarts; --now stops the
# services too (the keyboard and mouse the input relay carries drop out of SteamVR until then).
# on: puts back what off turned off, recorded in ~/.local/state/frametop/disabled; nothing that
# was never installed. SteamVR loads the driver and starts the services when it next starts.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$root/scripts/_env.sh"

mode=${1:-on}
now=0
case $mode in
  on | off | status) [ $# -eq 0 ] || shift ;;
  *) echo "usage: $0 [on|off [--now]|status]" >&2; exit 2 ;;
esac
for arg in "$@"; do
  case $arg in
    --now) [ "$mode" = off ] || { echo "--now only goes with off" >&2; exit 2; }; now=1 ;;
    *) echo "usage: $0 [on|off [--now]|status]" >&2; exit 2 ;;
  esac
done

on_frame_script "$mode" "$now" "$FRAME_REPO" <<'HOST'
set -euo pipefail
mode=$1 now=$2 repo=$3
state=$HOME/.local/state/frametop/disabled
apps=$HOME/.local/share/applications
driver=$HOME/.local/share/frametop/ft_pointer
vrpaths=$HOME/.config/openvr/openvrpaths.vrpath
reg=/opt/steamvr/bin/linuxarm64/vrpathreg
# SteamVR's registry tool with SteamVR's config folder and libraries (pointer/driver/install.sh
# says why the folder matters inside the Frametop desktop).
vrpathreg() { env XDG_CONFIG_HOME="$HOME/.config" LD_LIBRARY_PATH=/opt/steamvr/bin/linuxarm64 "$reg" "$@"; }
registered() { grep -qs "\"$driver\"" "$vrpaths"; }

case $mode in
  status)
    if [ -f "$state" ]; then
      echo "Frametop is disabled (./enable.sh turns it on). Off:"
      sed 's/^/  /' "$state"
    else
      echo "Frametop is enabled."
      for f in "$HOME"/.config/systemd/user/frametop-*.service; do
        [ -e "$f" ] || continue
        u=$(basename "$f")
        echo "  $u: $(systemctl --user is-enabled "$u" 2>/dev/null || true), $(systemctl --user is-active "$u" 2>/dev/null || true)"
      done
      registered && echo "  3D mouse driver: registered with SteamVR" || echo "  3D mouse driver: not registered with SteamVR"
      [ -f "$apps/frametop.desktop" ] && echo "  launcher: Launch a program -> Frametop" || echo "  launcher: no Frametop entry"
    fi ;;

  off)
    [ -f "$state" ] && { echo "Frametop is disabled already (./enable.sh turns it on)."; exit 0; }
    lines=() units=()
    for f in "$HOME"/.config/systemd/user/frametop-*.service; do
      [ -e "$f" ] || continue
      u=$(basename "$f")
      [ "$(systemctl --user is-enabled "$u" 2>/dev/null)" = enabled ] || continue
      units+=("$u"); lines+=("unit $u")
    done
    if [ ${#units[@]} -gt 0 ]; then
      systemctl --user disable "${units[@]}" 2>/dev/null
      if [ "$now" = 1 ]; then
        systemctl --user stop "${units[@]}" 2>/dev/null || true
        echo "stopped and disabled: ${units[*]}"
      else
        echo "disabled (they keep running until SteamVR restarts): ${units[*]}"
      fi
    fi
    if registered; then
      if [ -x "$reg" ] && vrpathreg removedriver "$driver" >/dev/null 2>&1; then
        lines+=("driver"); echo "unregistered the 3D mouse's driver from SteamVR (it unloads when SteamVR restarts)"
      else
        echo "warning: couldn't unregister the 3D mouse's driver (SteamVR's vrpathreg); it stays loaded" >&2
      fi
    fi
    if [ -f "$apps/frametop.desktop" ]; then
      # Recorded with the session script it ran, so on puts it back for the same install.
      session=$(sed -n 's/^Exec=//p' "$apps/frametop.desktop" | head -1)
      rm -f "$apps/frametop.desktop"; lines+=("launcher $session"); echo "removed Launch a program -> Frametop"
    fi
    profiles=("$apps"/frametop-profile-*.desktop)
    if [ -e "${profiles[0]}" ]; then
      rm -f "${profiles[@]}"; lines+=("profiles"); echo "removed the profiles' launcher entries (${#profiles[@]})"
    fi
    [ ${#lines[@]} -gt 0 ] || { echo "Nothing of Frametop was on. Is it installed?"; exit 0; }
    mkdir -p "$(dirname "$state")"
    printf '%s\n' "${lines[@]}" > "$state"
    echo "Frametop is disabled: it won't start with SteamVR or show in Launch a program. ./enable.sh turns it on again." ;;

  on)
    [ -f "$state" ] || { echo "Frametop isn't disabled (./enable.sh status)."; exit 0; }
    units=() app=$repo
    while read -r kind name; do
      case $kind in
        unit)
          if [ -e "$HOME/.config/systemd/user/$name" ]; then units+=("$name")
          else echo "warning: $name is gone; ./install.sh puts it back" >&2; fi ;;
        driver)
          if [ -d "$driver" ] && [ -x "$reg" ]; then
            # vrpathreg runs xdg-open for SteamVR's desktop monitor, which the Frame doesn't have.
            noopen=$(mktemp -d)
            printf '#!/bin/sh\nexit 0\n' > "$noopen/xdg-open"; chmod +x "$noopen/xdg-open"
            if PATH=$noopen:$PATH vrpathreg adddriver "$driver" >/dev/null 2>&1; then
              echo "registered the 3D mouse's driver with SteamVR again"
            else
              echo "warning: couldn't register the 3D mouse's driver; pointer/driver/install.sh install does it" >&2
            fi
            rm -rf "$noopen"
          else
            echo "warning: the 3D mouse's driver is gone; pointer/driver/install.sh install puts it back" >&2
          fi ;;
        launcher)
          # The install the entry ran from (the installed copy, usually), if it's still there.
          [ -n "$name" ] && [ -f "$name" ] && app=$(cd "$(dirname "$name")/.." && pwd)
          if [ -f "$app/session/frametop.desktop" ]; then
            mkdir -p "$apps"
            sed "s|@SESSION@|$app/session/frametop-session.sh|" "$app/session/frametop.desktop" > "$apps/frametop.desktop"
            echo "Launch a program -> Frametop is back ($app)"
          else
            echo "warning: no $app/session/frametop.desktop; ./desktops.sh install adds the launcher entry" >&2
          fi ;;
        profiles)
          [ -x "$app/layout/ft-layout" ] && "$app/layout/ft-layout" launchers ;;
      esac
    done < "$state"
    if [ ${#units[@]} -gt 0 ]; then
      systemctl --user enable "${units[@]}" 2>/dev/null
      echo "enabled: ${units[*]}"
    fi
    rm -f "$state"
    echo "Frametop is on again. Restart SteamVR (or the headset) to load the 3D mouse driver and start the services." ;;
esac
HOST

if [ "$mode" = on ] && [ -t 0 ]; then
  read -r -p "Restart SteamVR now? It closes everything open in VR. [y/N] " answer || answer=
  [[ $answer =~ ^[Yy] ]] && on_frame 'systemctl --user restart steamvr.service'
fi
exit 0
