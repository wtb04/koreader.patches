#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy-patches.sh <host>
#   ./deploy-patches.sh <host> <port>
#
# Optional environment overrides:
#   SSH_USER (default: root)
#   REMOTE_PATCH_DIR (default: /mnt/onboard/.adds/koreader/patches)

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <host> [port]"
  exit 1
fi

HOST="$1"
PORT="${2:-2222}"
SSH_USER="${SSH_USER:-root}"
REMOTE_PATCH_DIR="${REMOTE_PATCH_DIR:-/mnt/onboard/.adds/koreader/patches}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Clearing remote patches in ${REMOTE_PATCH_DIR} on ${SSH_USER}@${HOST}:${PORT}..."
ssh -p "${PORT}" "${SSH_USER}@${HOST}" \
  "mkdir -p '${REMOTE_PATCH_DIR}' && rm -rf '${REMOTE_PATCH_DIR}'/*"

echo "Uploading local .lua patches from ${SCRIPT_DIR}..."
scp -P "${PORT}" "${SCRIPT_DIR}"/*.lua "${SSH_USER}@${HOST}:${REMOTE_PATCH_DIR}/"

echo "Done."