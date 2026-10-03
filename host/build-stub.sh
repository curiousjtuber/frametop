#!/usr/bin/env bash
# In the copy install-host.sh makes, this replaces each component's build.sh: its programs
# in build/ are built already (README-host.md). To rebuild them, run install-host.sh again
# from a Frametop checkout.
echo "$(dirname "$(readlink -f "$0")")/build/: built by install-host.sh, nothing to build here"
