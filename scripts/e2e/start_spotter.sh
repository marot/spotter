#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

"${SCRIPT_DIR}/prepare_runtime.sh"

# Reset SQLite DB for clean E2E run (dev.exs: ../path/to/your.db relative to /app)
db_path="$(cd "${REPO_ROOT}" && realpath -m "../path/to/your.db")"
rm -f "${db_path}"

cd "${REPO_ROOT}"
mix ecto.migrate
mix spotter.e2e.seed
mix phx.server
