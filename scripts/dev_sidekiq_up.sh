#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/dev_services_up.sh"

(
  cd "$ROOT_DIR"
  bundle exec rails db:prepare
)

cd "$ROOT_DIR"
exec bundle exec sidekiq -C config/sidekiq.yml
