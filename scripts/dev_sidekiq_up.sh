#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  . "$ROOT_DIR/.env"
  set +a
fi

export NEWS_TRANSLATOR_BASE_URL="${NEWS_TRANSLATOR_BASE_URL:-http://127.0.0.1:19191}"
export NEWS_GAME_ID_BASE_URL="${NEWS_GAME_ID_BASE_URL:-http://127.0.0.1:19192}"

if [ "${NEWS_TRANSLATOR_BASE_URL:-}" = "http://127.0.0.1:19191" ] && ! curl -fsS --max-time 1 http://127.0.0.1:19191/health >/dev/null 2>&1; then
  if curl -fsS --max-time 1 http://127.0.0.1:8008/health >/dev/null 2>&1; then
    export NEWS_TRANSLATOR_BASE_URL="http://127.0.0.1:8008"
  fi
fi

stop_sidekiq() {
  local pids=""

  pids="$(pgrep -f "bundle exec sidekiq -C config/sidekiq.yml" || true)"
  if [ -z "$pids" ]; then
    pids="$(pgrep -f "bundle exec sidekiq" || true)"
  fi

  if [ -n "$pids" ]; then
    echo "Stopping existing Sidekiq ($pids)"
    kill $pids || true
    sleep 2
  fi

  pids="$(pgrep -f "bundle exec sidekiq" || true)"
  if [ -n "$pids" ]; then
    echo "Force stopping existing Sidekiq ($pids)"
    kill -9 $pids || true
  fi
}

stop_sidekiq

"$ROOT_DIR/scripts/dev_services_up.sh"

(
  cd "$ROOT_DIR"
  bundle exec rails db:prepare
)

cd "$ROOT_DIR"
exec bundle exec sidekiq -C config/sidekiq.yml
