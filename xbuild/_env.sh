# Sourced by the xbuild scripts that run zig. Puts the zig xbuild/mise.toml pins first on
# PATH, through mise when it's installed (the dev box shares the home folder, so the host's
# mise works there), else Fedora's zig in the box; stops if the zig found isn't that version.
want=$(sed -n 's/^zig *= *"\(.*\)"/\1/p' "$here/mise.toml")
mise=$(command -v mise || echo "$HOME/.local/bin/mise")
if [ -x "$mise" ]; then
  # Trusting this file is the scripts' own call; it pins a tool and nothing else.
  export MISE_TRUSTED_CONFIG_PATHS=$here/mise.toml${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}
  "$mise" -C "$here" install -q zig
  PATH=$(dirname "$("$mise" -C "$here" which zig)"):$PATH
fi
have=$(zig version 2>/dev/null) || { echo "xbuild needs zig $want: install mise, or zig on PATH" >&2; exit 1; }
[ "$have" = "$want" ] ||
  { echo "xbuild needs zig $want (xbuild/mise.toml), not $have: install mise to get it" >&2; exit 1; }
