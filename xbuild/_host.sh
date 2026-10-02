# Sourced by xbuild/ and install-cross.sh: where this runs, and how to reach the Frame host.
#   where=frame      on the Frame host itself (SteamOS, VR variant)
#   where=frame-box  in a container on the Frame (a distrobox, the dev box or any other):
#                    distrobox-host-exec reaches the host, and the home folder is shared
#   where=other      a PC, or a container on one: the Frame is $FRAME_HOST, over SSH
# box is the container's name, empty outside one.
is_frame() { grep -qx 'ID=steamos' "$1" 2>/dev/null && grep -qE '^VARIANT_ID="?vr"?$' "$1"; }
box=$(sed -n 's/^name="\(.*\)"$/\1/p' /run/.containerenv 2>/dev/null || true)
if [ -e /run/.containerenv ]; then
  if is_frame /run/host/etc/os-release; then where=frame-box; else where=other; fi
elif is_frame /etc/os-release; then
  where=frame
else
  where=other
fi
FRAME_HOST=${FRAME_HOST:-frame}

# on_host [-t] 'command': run a shell command on the Frame host, from the home folder, with
# the real XDG_RUNTIME_DIR and user bus (a terminal in a VR desktop has its session's own).
# -t gives it a terminal over SSH, for sudo's password.
on_host() {
  local t= cmd
  [ "$1" = -t ] && { t=-t; shift; }
  cmd='export XDG_RUNTIME_DIR=/run/user/$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
'$1
  case $where in
    frame) (cd && bash -c "$cmd") ;;
    frame-box) (cd && distrobox-host-exec bash -c "$cmd") ;;
    other) ssh $t -o BatchMode=yes "$FRAME_HOST" "bash -c $(printf %q "$cmd")" ;;
  esac
}
