#!/usr/bin/env bash
# In the copy install-cross.sh makes, this replaces each component's build.sh: its programs
# in build/ are cross-compiled already (README-cross.md). To rebuild them, run
# install-cross.sh again from a Frametop checkout.
echo "$(dirname "$(readlink -f "$0")")/build/: cross-compiled by install-cross.sh, nothing to build here"
