#!/usr/bin/env bash
# Notifies Spotter of the session_id <-> pane_id mapping.
# Reads session JSON from stdin, extracts session_id.
# Sends POST to Spotter's session-start endpoint.
# Fails silently if server is not running.

set -euo pipefail

# Read the session JSON from stdin
INPUT="$(cat)"

# Extract session_id from the JSON input
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"

if [ -z "${SESSION_ID:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

# Determine the Spotter port from the worktree .port file
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

# POST the mapping to Spotter (fail silently)
curl -s -o /dev/null -X POST \
  "http://127.0.0.1:${PORT}/api/hooks/session-start" \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"${SESSION_ID}\", \"pane_id\": \"${TMUX_PANE}\"}" \
  --connect-timeout 2 \
  --max-time 4 \
  2>/dev/null || true
