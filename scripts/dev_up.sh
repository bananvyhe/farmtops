#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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
