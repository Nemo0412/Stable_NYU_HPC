#!/usr/bin/env bash
# Thin wrapper — VS Code only. Prefer ./preinstall-remote-server.sh for options.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/preinstall-remote-server.sh" --editor vscode "$@"
