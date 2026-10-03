# Sourced by the xbuild scripts that run zig or meson. Puts the tools xbuild/mise.toml pins
# first on PATH, through mise when it's installed (a distrobox shares the home folder, so
# the host's mise works there). Without mise, zig on PATH must be the pinned version (in the
# dev box, Fedora's), and meson at least 1.10; it stops otherwise.
want=$(sed -n 's/^zig *= *"\(.*\)"/\1/p' "$here/mise.toml")
mise=$(command -v mise || echo "$HOME/.local/bin/mise")
if [ -x "$mise" ]; then
  # Trusting this file is the scripts' own call; it pins tools and nothing else.
  export MISE_TRUSTED_CONFIG_PATHS=$here/mise.toml${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}
  "$mise" -C "$here" install -q
  eval "$("$mise" -C "$here" env -s bash)"
fi
have=$(zig version 2>/dev/null) || { echo "xbuild needs zig $want: install mise, or zig on PATH" >&2; exit 1; }
[ "$have" = "$want" ] ||
  { echo "xbuild needs zig $want (xbuild/mise.toml), not $have: install mise to get it" >&2; exit 1; }
