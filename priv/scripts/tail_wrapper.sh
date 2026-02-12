#!/usr/bin/env bash
# Wrapper around tail -F for use as an Erlang Port.
# Ensures clean shutdown on SIGTERM/SIGHUP.
set -euo pipefail

FILE="$1"

cleanup() {
  kill %1 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGHUP SIGINT

tail -n 0 -F "$FILE" &
wait
