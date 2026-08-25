#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.dev.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.development}"
DOCKER_CONTEXT="${DOCKER_CONTEXT:-default}"
EDITOR_COMMAND="${EDITOR:-nano}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Create it from .env.development.example first." >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/config/master.key" ]]; then
  echo "Missing $ROOT_DIR/config/master.key." >&2
  exit 1
fi

exec docker --context "$DOCKER_CONTEXT" compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  run --rm --no-deps \
  -e "EDITOR=$EDITOR_COMMAND" \
  -e "RAILS_MASTER_KEY=$(tr -d '\r\n' < "$ROOT_DIR/config/master.key")" \
  -v "$ROOT_DIR:/rails" \
  web bundle exec rails credentials:edit "$@"
