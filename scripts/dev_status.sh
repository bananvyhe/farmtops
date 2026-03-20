#!/bin/zsh
set -euo pipefail

PG_BIN="$HOME/.local/share/mise/installs/postgres/16.12/bin"
REDIS_BIN="$HOME/.local/share/mise/installs/redis/7.4.8/bin"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PG_DATA="$ROOT_DIR/.dev/postgres"
PG_HOST="${PGHOST:-127.0.0.1}"
PG_PORT="${PGPORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"

if [ -d "$PG_DATA" ]; then
  "$PG_BIN/pg_ctl" -D "$PG_DATA" status || true
fi

"$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping || true
