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
REDIS_PASSWORD="$(bundle exec rails runner 'print RuntimeConfig.redis_password.to_s' 2>/dev/null || true)"

mkdir -p "$DEV_DIR" "$ROOT_DIR/log" "$REDIS_DATA"

if [ ! -d "$PG_DATA/base" ]; then
  "$PG_BIN/initdb" -D "$PG_DATA" >/dev/null
  echo "listen_addresses = '$PG_HOST'" >> "$PG_DATA/postgresql.conf"
  echo "port = $PG_PORT" >> "$PG_DATA/postgresql.conf"
fi

postgres_available() {
  if "$PG_BIN/pg_isready" -h "$PG_HOST" -p "$PG_PORT" >/dev/null 2>&1; then
    return 0
  fi
  if command -v lsof >/dev/null 2>&1 && lsof -ti "tcp:$PG_PORT" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if postgres_available; then
  echo "PostgreSQL already available on $PG_HOST:$PG_PORT, skipping local start"
elif ! "$PG_BIN/pg_ctl" -D "$PG_DATA" status >/dev/null 2>&1; then
  if ! "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_LOG" start; then
    if postgres_available; then
      echo "PostgreSQL became available on $PG_HOST:$PG_PORT, continuing"
    else
      echo "Failed to start PostgreSQL. See $PG_LOG"
      exit 1
    fi
  fi
fi

cat > "$REDIS_CONF" <<EOF
bind $PG_HOST
port $REDIS_PORT
dir $REDIS_DATA
dbfilename dump.rdb
logfile $REDIS_LOG
daemonize yes
EOF

if [ -n "$REDIS_PASSWORD" ]; then
  printf 'requirepass %s\n' "$REDIS_PASSWORD" >> "$REDIS_CONF"
fi

redis_needs_restart=0
if [ -n "$REDIS_PASSWORD" ]; then
  if "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" --pass "$REDIS_PASSWORD" --no-auth-warning ping >/dev/null 2>&1; then
    redis_needs_restart=0
  elif "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    redis_needs_restart=1
  else
    redis_needs_restart=1
  fi
else
  if "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    redis_needs_restart=0
  else
    redis_needs_restart=1
  fi
fi

if [ "$redis_needs_restart" -eq 1 ]; then
  if [ -n "$REDIS_PASSWORD" ] && "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" --pass "$REDIS_PASSWORD" --no-auth-warning ping >/dev/null 2>&1; then
    "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" --pass "$REDIS_PASSWORD" --no-auth-warning shutdown >/dev/null 2>&1 || true
  elif "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    "$REDIS_BIN/redis-cli" -h "$PG_HOST" -p "$REDIS_PORT" shutdown >/dev/null 2>&1 || true
  fi
  "$REDIS_BIN/redis-server" "$REDIS_CONF"
fi

echo "PostgreSQL: $PG_HOST:$PG_PORT"
echo "Redis: $PG_HOST:$REDIS_PORT"
