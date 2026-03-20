#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="$ROOT_DIR/.dev"
PG_BIN="$HOME/.local/share/mise/installs/postgres/16.12/bin"
REDIS_BIN="$HOME/.local/share/mise/installs/redis/7.4.8/bin"
PG_DATA="$DEV_DIR/postgres"
PG_LOG="$ROOT_DIR/log/postgres.log"
PG_PORT="${PGPORT:-5432}"
PG_HOST="${PGHOST:-127.0.0.1}"
PG_USER="${PGUSER:-$USER}"
REDIS_DIR="$DEV_DIR/redis"
REDIS_DATA="$REDIS_DIR/data"
REDIS_CONF="$REDIS_DIR/redis.conf"
REDIS_LOG="$ROOT_DIR/log/redis.log"
REDIS_PORT="${REDIS_PORT:-6379}"

mkdir -p "$DEV_DIR" "$ROOT_DIR/log" "$REDIS_DATA"

if [ ! -d "$PG_DATA/base" ]; then
  "$PG_BIN/initdb" -D "$PG_DATA" >/dev/null
  echo "listen_addresses = '$PG_HOST'" >> "$PG_DATA/postgresql.conf"
  echo "port = $PG_PORT" >> "$PG_DATA/postgresql.conf"
fi

if ! "$PG_BIN/pg_ctl" -D "$PG_DATA" status >/dev/null 2>&1; then
  "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_LOG" start
fi

cat > "$REDIS_CONF" <<EOF
bind $PG_HOST
port $REDIS_PORT
dir $REDIS_DATA
dbfilename dump.rdb
logfile $REDIS_LOG
daemonize yes
EOF

if ! "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
  "$REDIS_BIN/redis-server" "$REDIS_CONF"
fi

echo "PostgreSQL: $PG_HOST:$PG_PORT"
echo "Redis: $PG_HOST:$REDIS_PORT"
