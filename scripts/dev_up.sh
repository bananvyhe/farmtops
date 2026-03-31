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

"$ROOT_DIR/scripts/dev_services_up.sh"

(
  cd "$ROOT_DIR"
  bundle exec rails db:prepare
) &

(
  cd "$ROOT_DIR"
  bundle exec rails server -b 127.0.0.1 -p 3000
) &

(
  cd "$ROOT_DIR"
  bundle exec sidekiq -C config/sidekiq.yml
) &

(
  cd "$ROOT_DIR/frontend"
  npm run dev -- --host 127.0.0.1
) &

wait
