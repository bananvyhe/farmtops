#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

stop_pids() {
  local pattern="$1"
  local label="$2"
  local pids=""

  pids="$(pgrep -f "$pattern" || true)"
  if [ -n "$pids" ]; then
    echo "Stopping $label ($pids)"
    kill $pids || true
  fi
}

stop_port() {
  local port="$1"
  local label="$2"

  if command -v lsof >/dev/null 2>&1; then
    local pids=""
    pids="$(lsof -ti "tcp:$port" || true)"
    if [ -n "$pids" ]; then
      echo "Stopping $label on :$port ($pids)"
      kill $pids || true
    fi
  fi
}

stop_pids "bundle exec rails server" "Rails server"
stop_pids "bundle exec sidekiq" "Sidekiq"
stop_pids "npm run dev -- --host 127.0.0.1" "Vite dev server"

stop_port 3000 "Rails server"
stop_port 5173 "Vite dev server"

"$ROOT_DIR/scripts/dev_services_down.sh"
