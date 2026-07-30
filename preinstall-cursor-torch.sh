#!/usr/bin/env bash
# Download + pre-extract Cursor Server on torch scratch so Remote-SSH does not time out.
# Run after: ignite   (SSH auth / ControlMaster must be up)
#
# Usage:
#   ./preinstall-cursor-torch.sh [host]
# Env:
#   CURSOR_INSTALL_ROOT  Override remote install root
#                        (default: /scratch/$REMOTE_USER/cursor-server/.cursor-server)
set -euo pipefail

HOST="${1:-torch}"
REMOTE_USER="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "${HOST}" 'whoami')"
INSTALL_ROOT="${CURSOR_INSTALL_ROOT:-/scratch/${REMOTE_USER}/cursor-server/.cursor-server}"
COMMIT="042b3c1a4c53f2c3808067f519fbfc67b72cad80"
# Prefer commit from local Cursor.app if present
if [[ -f /Applications/Cursor.app/Contents/Resources/app/product.json ]]; then
  COMMIT="$(python3 -c "import json; print(json.load(open('/Applications/Cursor.app/Contents/Resources/app/product.json'))['commit'])")"
fi
URL="https://downloads.cursor.com/production/${COMMIT}/linux/x64/cursor-reh-linux-x64.tar.gz"
LOCAL_TAR="$(mktemp -t cursor-server-XXXXXX).tar.gz"
REMOTE_TAR="${INSTALL_ROOT}/cursor-server-preinstall.tar.gz"
TARGET="${INSTALL_ROOT}/bin/linux-x64/${COMMIT}"

cleanup() { rm -f "${LOCAL_TAR}"; }
trap cleanup EXIT

echo "==> Cursor commit: ${COMMIT}"
echo "==> Remote user: ${REMOTE_USER}"
echo "==> Install root: ${INSTALL_ROOT}"
echo "==> Checking SSH to ${HOST}..."
ssh -o BatchMode=yes -o ConnectTimeout=20 "${HOST}" "echo connected: \$(hostname)"

# Skip if already installed
if ssh -o BatchMode=yes "${HOST}" "test -x '${TARGET}/node' && test -f '${TARGET}/bin/cursor-server'"; then
  echo "==> Server already extracted at ${TARGET}"
  ssh -o BatchMode=yes "${HOST}" "'${TARGET}/node' -v"
  echo "==> Done. Connect Cursor Remote-SSH to ${HOST}."
  exit 0
fi

echo "==> Downloading server (~107MB) from Cursor CDN..."
curl -fL --progress-bar -o "${LOCAL_TAR}" "${URL}"
ls -lh "${LOCAL_TAR}"

echo "==> Creating remote dirs..."
ssh -o BatchMode=yes "${HOST}" "mkdir -p '${INSTALL_ROOT}/bin/linux-x64' && rm -f /run/user/\$(id -u)/cursor-remote-lock.* 2>/dev/null; pkill -u \"\$(id -un)\" -f 'tar -xf cursor-server' 2>/dev/null || true"

echo "==> Uploading to ${REMOTE_TAR} (may take a few minutes)..."
scp -o BatchMode=yes "${LOCAL_TAR}" "${HOST}:${REMOTE_TAR}"

echo "==> Extracting on remote (this can be slow on network FS)..."
ssh -o BatchMode=yes "${HOST}" "bash -lc '
  set -euo pipefail
  mkdir -p \"${TARGET}\"
  tar -xf \"${REMOTE_TAR}\" -C \"${TARGET}\" --strip-components=1
  rm -f \"${REMOTE_TAR}\"
  test -x \"${TARGET}/node\"
  \"${TARGET}/node\" -v
  ls \"${TARGET}/bin/cursor-server\"
'"

echo "==> Done. Point remote.SSH.serverInstallPath.${HOST} at /scratch/${REMOTE_USER}/cursor-server"
echo "    then Connect Cursor Remote-SSH to ${HOST}."
