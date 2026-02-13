#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$SCRIPT_DIR/../agent"
ENTRY="$AGENT_DIR/dist/index.js"

if [ ! -f "$ENTRY" ]; then
  echo "ERROR: $ENTRY not found. Run: (cd agent && npm ci && npm run build)" >&2
  exit 1
fi

exec node "$ENTRY"
