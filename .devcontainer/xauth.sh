#!/usr/bin/env bash
# Writes a fresh X cookie to a stable path for the dev container to mount.
# Run automatically via "initializeCommand"; can also be run by hand.
set -euo pipefail
umask 077

: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}"
dest="$XDG_RUNTIME_DIR/px4-devcontainer.xauth"

rm -f "$dest"
if [ -n "${DISPLAY:-}" ]; then
  xauth nlist "$DISPLAY" 2>/dev/null |
    sed 's/^..../ffff/' |
    xauth -f "$dest" nmerge - 2>/dev/null || true
fi

# The mount source must exist; an empty file is fine if the X server needs no cookie.
if [ ! -s "$dest" ]; then
  echo "warning: no Xauthority cookie for '${DISPLAY:-}'; continuing without one." >&2
  : > "$dest"
fi
