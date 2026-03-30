#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REDIS_BIN="$HOME/.local/share/mise/installs/redis/7.4.8/bin"
PG_HOST="${PGHOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DB="${REDIS_DB:-0}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

stop_sidekiq() {
  local pids=""

  pids="$(pgrep -f "bundle exec sidekiq -C config/sidekiq.yml" || true)"
  if [ -z "$pids" ]; then
    pids="$(pgrep -f "bundle exec sidekiq" || true)"
  fi

  if [ -n "$pids" ]; then
    echo "Stopping Sidekiq ($pids)"
    kill $pids || true
    sleep 2
  fi

  pids="$(pgrep -f "bundle exec sidekiq" || true)"
  if [ -n "$pids" ]; then
    echo "Force stopping Sidekiq ($pids)"
    kill -9 $pids || true
  fi
}

redis_ping_args=(
  -h "$PG_HOST"
  -p "$REDIS_PORT"
  -n "$REDIS_DB"
)

redis_flush_args=(
  -h "$PG_HOST"
  -p "$REDIS_PORT"
  -n "$REDIS_DB"
)

if [ -n "$REDIS_PASSWORD" ]; then
  redis_ping_args+=(--pass "$REDIS_PASSWORD" --no-auth-warning)
  redis_flush_args+=(--pass "$REDIS_PASSWORD" --no-auth-warning)
fi

stop_sidekiq

if "$REDIS_BIN/redis-cli" "${redis_ping_args[@]}" ping >/dev/null 2>&1; then
  echo "Flushing Redis DB $REDIS_DB (this removes Sidekiq queues, retries, schedules, locks, and other keys)"
  "$REDIS_BIN/redis-cli" "${redis_flush_args[@]}" flushdb
else
  echo "Redis is not reachable at $PG_HOST:$REDIS_PORT, skipping flush"
fi
