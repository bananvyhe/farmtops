#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_PORT="${FRONTEND_PORT:-8082}"
echo "Farmspot frontend: http://localhost:${FRONTEND_PORT}"
echo "Rails healthcheck: http://localhost:${WEB_PORT:-3002}/up"
exec "$ROOT_DIR/scripts/dev_docker.sh" up "$@"
