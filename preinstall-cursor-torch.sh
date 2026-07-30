#!/usr/bin/env bash
# Thin wrapper — Cursor only. Prefer ./preinstall-remote-server.sh for options.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/preinstall-remote-server.sh" --editor cursor "$@"
