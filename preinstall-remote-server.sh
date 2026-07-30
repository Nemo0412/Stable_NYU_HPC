#!/usr/bin/env bash
# Pre-install or relocate Remote-SSH servers on Torch scratch.
# Optional — plain SSH / scp / rsync only need `ignite`, not this script.
#
# Usage:
#   ./preinstall-remote-server.sh [options] [host]
#
# Options:
#   --editor cursor|vscode|both   What to prepare (default: both)
#   --method local|remote|symlink
#       local   Download on your laptop, scp, extract on host (default; most reliable)
#       remote  curl on the login node (needs outbound HTTPS from Torch)
#       symlink Only mkdir on scratch + symlink ~/.cursor-server / ~/.vscode-server
#               Let the IDE install itself on next connect (no CDN from this script)
#   --root DIR  Scratch parent, default /scratch/$REMOTE_USER
#   -h, --help
#
# Env overrides:
#   REMOTE_EDITOR_ROOT   same as --root
#   CURSOR_COMMIT / VSCODE_COMMIT   pin commits explicitly
set -euo pipefail

HOST="torch"
EDITORS="both"
METHOD="local"
ROOT_OVERRIDE="${REMOTE_EDITOR_ROOT:-}"

usage() {
  awk 'NR==1 {next} /^#/ {sub(/^# ?/,""); print; next} {exit}' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --editor) EDITORS="${2:?}"; shift 2 ;;
    --method) METHOD="${2:?}"; shift 2 ;;
    --root) ROOT_OVERRIDE="${2:?}"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      HOST="$1"
      shift
      ;;
  esac
done

case "$EDITORS" in cursor|vscode|both) ;; *)
  echo "Invalid --editor: $EDITORS (use cursor|vscode|both)" >&2; exit 1 ;;
esac
case "$METHOD" in local|remote|symlink) ;; *)
  echo "Invalid --method: $METHOD (use local|remote|symlink)" >&2; exit 1 ;;
esac

want_cursor=0
want_vscode=0
[[ "$EDITORS" == "cursor" || "$EDITORS" == "both" ]] && want_cursor=1
[[ "$EDITORS" == "vscode" || "$EDITORS" == "both" ]] && want_vscode=1

echo "==> Checking SSH to ${HOST}..."
REMOTE_USER="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "${HOST}" 'whoami')"
SCRATCH_ROOT="${ROOT_OVERRIDE:-/scratch/${REMOTE_USER}}"
echo "==> Remote user: ${REMOTE_USER}"
echo "==> Scratch root: ${SCRATCH_ROOT}"
echo "==> Editors: ${EDITORS}  method: ${METHOD}"
ssh -o BatchMode=yes "${HOST}" "echo connected: \$(hostname) && mkdir -p '${SCRATCH_ROOT}'"

# --- detect local commits ----------------------------------------------------
detect_cursor_commit() {
  if [[ -n "${CURSOR_COMMIT:-}" ]]; then
    echo "$CURSOR_COMMIT"
    return
  fi
  local product=""
  for product in \
    "/Applications/Cursor.app/Contents/Resources/app/product.json" \
    "${HOME}/.cursor-server/bin/product.json"
  do
    if [[ -f "$product" ]]; then
      python3 -c "import json; print(json.load(open('$product'))['commit'])"
      return
    fi
  done
  # Fallback: recent known commit (may lag your client — set CURSOR_COMMIT if needed)
  echo "24a12dbd9cabf48956ce5bb3dbd234e41385b3d0"
}

detect_vscode_commit() {
  if [[ -n "${VSCODE_COMMIT:-}" ]]; then
    echo "$VSCODE_COMMIT"
    return
  fi
  local product=""
  for product in \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/product.json" \
    "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/product.json"
  do
    if [[ -f "$product" ]]; then
      python3 -c "import json; print(json.load(open('$product'))['commit'])"
      return
    fi
  done
  if command -v code >/dev/null 2>&1; then
    # `code -v` → version, commit, arch
    code -v 2>/dev/null | sed -n '2p' | tr -d '\r' && return
  fi
  echo ""
}

# Paths under scratch (parent that remote.SSH.serverInstallPath should point at)
CURSOR_PARENT="${SCRATCH_ROOT}/cursor-server"
VSCODE_PARENT="${SCRATCH_ROOT}/vscode-server"
# Actual extract roots (match IDE layouts)
CURSOR_DOT="${CURSOR_PARENT}/.cursor-server"
VSCODE_DOT="${VSCODE_PARENT}/.vscode-server"

setup_symlink_home() {
  local home_name="$1"   # .cursor-server or .vscode-server
  local scratch_dot="$2"
  ssh -o BatchMode=yes "${HOST}" "bash -s" <<EOF
set -euo pipefail
HOME_LINK="\$HOME/${home_name}"
SCRATCH_DOT="${scratch_dot}"
mkdir -p "\$SCRATCH_DOT"
if [[ -L "\$HOME_LINK" ]]; then
  echo "  symlink ok: \$HOME_LINK -> \$(readlink "\$HOME_LINK")"
elif [[ -e "\$HOME_LINK" ]]; then
  echo "  moving existing \$HOME_LINK -> \$SCRATCH_DOT (may take a while)..."
  # Merge into scratch if both exist
  rsync -a "\$HOME_LINK"/ "\$SCRATCH_DOT"/ 2>/dev/null || cp -a "\$HOME_LINK"/. "\$SCRATCH_DOT"/
  rm -rf "\$HOME_LINK"
  ln -s "\$SCRATCH_DOT" "\$HOME_LINK"
  echo "  linked \$HOME_LINK -> \$SCRATCH_DOT"
else
  ln -s "\$SCRATCH_DOT" "\$HOME_LINK"
  echo "  created \$HOME_LINK -> \$SCRATCH_DOT"
fi
EOF
}

install_cursor_local_or_remote() {
  local commit method
  commit="$(detect_cursor_commit)"
  method="$1"
  local target="${CURSOR_DOT}/bin/linux-x64/${commit}"
  local url="https://downloads.cursor.com/production/${commit}/linux/x64/cursor-reh-linux-x64.tar.gz"
  local remote_tar="${CURSOR_DOT}/cursor-server-preinstall.tar.gz"
  local bin_check="bin/cursor-server"

  echo ""
  echo "==> Cursor commit: ${commit}"
  if ssh -o BatchMode=yes "${HOST}" "test -x '${target}/node' && test -f '${target}/${bin_check}'"; then
    echo "==> Cursor already at ${target}"
    ssh -o BatchMode=yes "${HOST}" "'${target}/node' -v"
    return 0
  fi

  ssh -o BatchMode=yes "${HOST}" "mkdir -p '${CURSOR_DOT}/bin/linux-x64' && rm -f /run/user/\$(id -u)/cursor-remote-lock.* 2>/dev/null || true"

  if [[ "$method" == "remote" ]]; then
    echo "==> Downloading Cursor on remote..."
    ssh -o BatchMode=yes "${HOST}" "bash -s" <<EOF
set -euo pipefail
curl -fL --progress-bar -o "${remote_tar}" "${url}"
mkdir -p "${target}"
tar -xf "${remote_tar}" -C "${target}" --strip-components=1
rm -f "${remote_tar}"
test -x "${target}/node"
"${target}/node" -v
test -f "${target}/${bin_check}"
EOF
  else
    local local_tar
    local_tar="$(mktemp -t cursor-server-XXXXXX).tar.gz"
    echo "==> Downloading Cursor on laptop..."
    curl -fL --progress-bar -o "${local_tar}" "${url}"
    echo "==> Uploading..."
    scp -o BatchMode=yes "${local_tar}" "${HOST}:${remote_tar}"
    rm -f "${local_tar}"
    echo "==> Extracting on remote..."
    ssh -o BatchMode=yes "${HOST}" "bash -s" <<EOF
set -euo pipefail
mkdir -p "${target}"
tar -xf "${remote_tar}" -C "${target}" --strip-components=1
rm -f "${remote_tar}"
test -x "${target}/node"
"${target}/node" -v
test -f "${target}/${bin_check}"
EOF
  fi
  echo "==> Cursor ready. Set remote.SSH.serverInstallPath.${HOST} = ${CURSOR_PARENT}"
}

install_vscode_local_or_remote() {
  local commit method
  commit="$(detect_vscode_commit)"
  method="$1"
  if [[ -z "$commit" ]]; then
    echo "==> WARN: Could not detect VS Code commit. Install VS Code locally or set VSCODE_COMMIT." >&2
    echo "    Skipping VS Code preinstall (symlink method still works)." >&2
    return 0
  fi
  local target="${VSCODE_DOT}/bin/${commit}"
  local url="https://update.code.visualstudio.com/commit:${commit}/server-linux-x64/stable"
  local remote_tar="${VSCODE_DOT}/vscode-server-preinstall.tar.gz"
  local bin_check="bin/code-server"

  echo ""
  echo "==> VS Code commit: ${commit}"
  if ssh -o BatchMode=yes "${HOST}" "test -x '${target}/node' && test -f '${target}/${bin_check}'"; then
    echo "==> VS Code already at ${target}"
    ssh -o BatchMode=yes "${HOST}" "'${target}/node' -v"
    return 0
  fi

  ssh -o BatchMode=yes "${HOST}" "mkdir -p '${VSCODE_DOT}/bin'"

  if [[ "$method" == "remote" ]]; then
    echo "==> Downloading VS Code server on remote..."
    ssh -o BatchMode=yes "${HOST}" "bash -s" <<EOF
set -euo pipefail
curl -fL --progress-bar -o "${remote_tar}" "${url}"
mkdir -p "${target}"
tar -xf "${remote_tar}" -C "${target}" --strip-components=1
rm -f "${remote_tar}"
test -x "${target}/node"
"${target}/node" -v
test -f "${target}/${bin_check}"
EOF
  else
    local local_tar
    local_tar="$(mktemp -t vscode-server-XXXXXX).tar.gz"
    echo "==> Downloading VS Code server on laptop..."
    curl -fL --progress-bar -o "${local_tar}" "${url}"
    echo "==> Uploading..."
    scp -o BatchMode=yes "${local_tar}" "${HOST}:${remote_tar}"
    rm -f "${local_tar}"
    echo "==> Extracting on remote..."
    ssh -o BatchMode=yes "${HOST}" "bash -s" <<EOF
set -euo pipefail
mkdir -p "${target}"
tar -xf "${remote_tar}" -C "${target}" --strip-components=1
rm -f "${remote_tar}"
test -x "${target}/node"
"${target}/node" -v
test -f "${target}/${bin_check}"
EOF
  fi
  echo "==> VS Code ready. Set remote.SSH.serverInstallPath.${HOST} = ${VSCODE_PARENT}"
}

# --- run --------------------------------------------------------------------
if [[ "$METHOD" == "symlink" ]]; then
  echo ""
  echo "==> Symlink method: IDE will install itself under scratch on first connect"
  [[ "$want_cursor" -eq 1 ]] && setup_symlink_home ".cursor-server" "$CURSOR_DOT"
  [[ "$want_vscode" -eq 1 ]] && setup_symlink_home ".vscode-server" "$VSCODE_DOT"
  echo ""
  echo "Done. Optional: still set remote.SSH.serverInstallPath to avoid home entirely:"
  [[ "$want_cursor" -eq 1 ]] && echo "  Cursor:  ${CURSOR_PARENT}"
  [[ "$want_vscode" -eq 1 ]] && echo "  VS Code: ${VSCODE_PARENT}"
  exit 0
fi

[[ "$want_cursor" -eq 1 ]] && install_cursor_local_or_remote "$METHOD"
[[ "$want_vscode" -eq 1 ]] && install_vscode_local_or_remote "$METHOD"

echo ""
echo "==> All done. Terminal-only users can ignore IDE settings — ignite is enough."
if [[ "$want_cursor" -eq 1 ]]; then
  echo "Cursor settings snippet:"
  echo "  \"remote.SSH.serverInstallPath\": { \"${HOST}\": \"${CURSOR_PARENT}\" }"
fi
if [[ "$want_vscode" -eq 1 ]]; then
  echo "VS Code settings snippet:"
  echo "  \"remote.SSH.serverInstallPath\": { \"${HOST}\": \"${VSCODE_PARENT}\" }"
fi
