#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="$ROOT_DIR/.dev"
PG_BIN="$HOME/.local/share/mise/installs/postgres/16.12/bin"
REDIS_BIN="$HOME/.local/share/mise/installs/redis/7.4.8/bin"
PG_DATA="$DEV_DIR/postgres"
PG_HOST="${PGHOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="$(bundle exec rails runner 'print RuntimeConfig.redis_password.to_s' 2>/dev/null || true)"

if [ -d "$PG_DATA" ] && "$PG_BIN/pg_ctl" -D "$PG_DATA" status >/dev/null 2>&1; then
  "$PG_BIN/pg_ctl" -D "$PG_DATA" stop
fi

if [ -n "$REDIS_PASSWORD" ] && "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" --pass "$REDIS_PASSWORD" --no-auth-warning ping >/dev/null 2>&1; then
  "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" --pass "$REDIS_PASSWORD" --no-auth-warning shutdown
elif "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
  "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" shutdown
fi
