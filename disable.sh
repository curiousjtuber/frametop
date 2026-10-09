#!/usr/bin/env bash
# Turn Frametop off without uninstalling it: ./disable.sh [--now]. ./enable.sh turns it on.
exec "$(dirname "${BASH_SOURCE[0]}")/enable.sh" off "$@"
