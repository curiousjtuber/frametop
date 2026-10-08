#!/bin/bash
# Runs inside the dev container; setup/dev-container.sh runs it after installing the
# packages. Two of the container's Fedora packages break Remote Access as Fedora updates
# them, so this holds them at versions that work and puts them back after a container
# rebuild or a `dnf upgrade`. Safe to re-run: every step checks before changing anything.
#
# - FreeRDP stays at 3.31.1. FreeRDP 3.32 turns on extended security for server-side NLA
#   and krdpserver then rejects every login ("Could not find user in SAM database" in
#   /tmp/frametop-remote.log; FreeRDP issue 13567, KRdp merge request 248). 3.31.1 has
#   left Fedora's repos, so it comes from Fedora's build archive (koji). Once Fedora ships
#   a krdp with the fix: dnf versionlock delete freerdp freerdp-libs libwinpr; dnf upgrade.
# - krdp is rebuilt with patches/krdp-nla-postconnect.patch: 6.7.5 re-checks credentials
#   after NLA that FreeRDP 3.32 clients (krdc 26.08) no longer send, and rejects every login;
#   krdp master trusts NLA. Same mechanism as kpipewire's, below.
# - kpipewire is rebuilt with patches/kpipewire-cursor-bitmap-size.patch: it copies the
#   cursor bitmap with stride * height * 4 bytes, stride is already bytes, and with the
#   desktop's 256 px cursor the over-read runs off the mapped memory and krdpserver
#   segfaults as soon as a frame carries a cursor bitmap (coredumpctl list krdpserver on
#   the host). The rebuild needs rpm-build and kpipewire's build dependencies (about 40 MB)
#   and is skipped once Fedora's source no longer has the line.
#
# Usage: setup/container-pins.sh                                        (in the container)
#        ~/.local/bin/distrobox enter dev -- setup/container-pins.sh    (from the host)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
arch=$(uname -m)

[ -e /run/.containerenv ] || { echo "run this inside the dev container" >&2; exit 1; }

# lock PACKAGE...: hold each package at the version installed now.
lock() {
  for p; do
    sudo -n dnf versionlock delete -q "$p" >/dev/null 2>&1 || true
    sudo -n dnf versionlock add -q "$p"
  done
}

# --- FreeRDP 3.31.1 -------------------------------------------------------------------
# The libraries, and the devel packages krdp's rebuild (below) needs, which have to match them.
freerdp_ver=3.31.1-1.fc44
freerdp_pkgs="freerdp freerdp-libs libwinpr freerdp-devel libwinpr-devel"
koji=https://kojipkgs.fedoraproject.org/packages/freerdp/3.31.1/1.fc44/$arch
need=
for p in $freerdp_pkgs; do [ "$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$p" 2>/dev/null)" = "$freerdp_ver" ] || need="$need $p"; done
if [ -z "$need" ]; then
  echo "freerdp $freerdp_ver: in place"
else
  echo "freerdp: installing$need $freerdp_ver from koji (FreeRDP 3.32 breaks krdp's login)"
  tmp=$(mktemp -d)
  for p in $need; do
    curl -fsSL -o "$tmp/$p.rpm" "$koji/$p-$freerdp_ver.$arch.rpm"
  done
  sudo -n rpm -Uvh --oldpackage "$tmp"/*.rpm
  rm -rf "$tmp"
fi
# shellcheck disable=SC2086
lock $freerdp_pkgs

# --- Fedora packages rebuilt with a patch ----------------------------------------------
# rebuild NAME PATCH FILE BUG WHAT: Fedora's NAME rebuilt with patches/PATCH as a .frametop1
# release, with its -devel subpackage, and held there, as long as FILE in its source (a tar
# wildcard) still matches BUG;
# once it doesn't, the fix has shipped and the hold is dropped. The rebuild needs rpm-build and
# the package's build dependencies (a few dozen MB) and takes a few minutes on the Frame.
rebuild() {
  local name=$1 patch=$here/patches/$2 file=$3 bug=$4 what=$5 work src spec
  # Every subpackage of the build goes in (-libs, -devel: a later rebuild may build against
  # them, and dnf would otherwise pull the stock ones and the stock library with them).
  if rpm -q "$name" "$name-devel" 2>/dev/null | grep -c '\.frametop' | grep -qx 2; then
    echo "$name $(rpm -q --qf '%{VERSION}-%{RELEASE}' "$name"): patched build in place"
    lock "$name" "$name-devel"
    return
  fi
  work=$(mktemp -d "/tmp/$name-build.XXXXXX")
  # The lock on an earlier rebuild would hide Fedora's source package from dnf: skip it here.
  (cd "$work" && dnf download -q --source --disable-plugin=versionlock "$name")
  src=$(echo "$work/$name"-*.src.rpm)
  [ -f "$src" ] || { echo "$name: couldn't download Fedora's source package" >&2; exit 1; }
  mkdir -p "$work/rpmbuild"
  rpm -i --define "_topdir $work/rpmbuild" "$src"
  spec=$work/rpmbuild/SPECS/$name.spec
  local text
  text=$(tar -xf "$work/rpmbuild/SOURCES/$name"-*.tar.xz -O --wildcards "$file") ||
    { echo "$name: $file not found in Fedora's source tarball; update $0" >&2; exit 1; }
  if ! grep -q "$bug" <<< "$text"; then
    echo "$name: Fedora's source no longer needs $what; nothing to patch"
    for p in $(rpm -qa --qf '%{NAME}\n' "$name*"); do sudo -n dnf versionlock delete -q "$p" >/dev/null 2>&1 || true; done
    rm -rf "$work"
    return
  fi
  echo "$name: rebuilding $(basename "$src" .src.rpm) with $what (a few minutes)"
  grep -q '^%autosetup' "$spec" || { echo "$name.spec no longer uses %autosetup; update $0" >&2; exit 1; }
  sudo -n dnf install -y -q rpm-build 2>&1 | { grep -vE "already installed|^Nothing to do|^$" || true; }
  sudo -n dnf builddep -y -q "$src" 2>&1 | { grep -vE "already installed|^Nothing to do|^$" || true; }
  cp "$patch" "$work/rpmbuild/SOURCES/"
  sed -i -e 's/^\(Release:.*\)$/\1.frametop1/' \
         -e "/^Source0:/a Patch99: $(basename "$patch")" "$spec"
  rpmbuild --define "_topdir $work/rpmbuild" -bb "$spec" > "$work/build.log" 2>&1 ||
    { tail -30 "$work/build.log" >&2; echo "$name build failed; log: $work/build.log" >&2; exit 1; }
  local rpms pkgs
  rpms=$(ls "$work/rpmbuild/RPMS/$arch/"*.frametop1."$arch".rpm | grep -v -- '-debug\(info\|source\)-')
  # shellcheck disable=SC2086
  sudo -n rpm -Uvh --replacepkgs --oldpackage $rpms
  pkgs=$(for r in $rpms; do rpm -qp --qf '%{NAME}\n' "$r"; done)
  # shellcheck disable=SC2086
  lock $pkgs
  echo "$name: installed and held: $(echo $pkgs | tr '\n' ' ')"
  rm -rf "$work"
}

# kpipewire copies the cursor bitmap with stride * height * 4 bytes (stride is already bytes),
# over-reads past the metadata and segfaults on the desktop's 256 px cursor.
rebuild kpipewire kpipewire-cursor-bitmap-size.patch '*/src/pipewiresourcestream.cpp' \
  'bitmap->stride \* bitmap->size.height \* 4' "the cursor fix"
# krdp 6.7.5 re-checks the user and password from the Client Info PDU after NLA already verified
# them, and FreeRDP 3.32 clients (krdc 26.08) leave them out, so every login fails
# ("PostConnect for peer failed"); krdp master trusts NLA when PAM isn't in use.
rebuild krdp krdp-nla-postconnect.patch '*/src/RdpConnection.cpp' \
  'user.name == username && user.password == password' "the NLA post-connect fix"

echo "pins: $(dnf versionlock list 2>/dev/null | sed -n 's/^Package name: //p' | tr '\n' ' ')"
