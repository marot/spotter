#!/usr/bin/env bash
# Shared timeout defaults for synchronous hook HTTP calls.
# Timeout resolution precedence:
#   1. Per-script env override (e.g. SPOTTER_NOTIFY_CONNECT_TIMEOUT)
#   2. Shared env override (SPOTTER_HOOK_CONNECT_TIMEOUT / SPOTTER_HOOK_MAX_TIME)
#   3. Hard defaults (0.1s connect, 0.3s max)

SPOTTER_DEFAULT_CONNECT_TIMEOUT="0.1"
SPOTTER_DEFAULT_MAX_TIME="0.3"

# resolve_timeout <per_script_env_value> <shared_env_value> <default>
# Returns the first non-empty value in precedence order.
resolve_timeout() {
  local per_script="${1:-}"
  local shared="${2:-}"
  local default="$3"
  if [ -n "$per_script" ]; then
    echo "$per_script"
  elif [ -n "$shared" ]; then
    echo "$shared"
  else
    echo "$default"
  fi
}
