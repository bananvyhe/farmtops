#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Dedicated farmspot production target.
export DEPLOY_HOST="${DEPLOY_HOST:-root@81.163.29.109}"
export DEPLOY_PATH="${DEPLOY_PATH:-/srv/farmspot}"
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-.env.production}"

# Keep farmspot on its own local port so it does not collide with other sites.
export FRONTEND_PORT="${FRONTEND_PORT:-127.0.0.1:8082}"

"$ROOT_DIR/scripts/deploy_prod.sh" "$@"
