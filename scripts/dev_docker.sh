#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.dev.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.development}"
DOCKER_CONTEXT="${DOCKER_CONTEXT:-default}"

if docker --context "$DOCKER_CONTEXT" compose version >/dev/null 2>&1; then
  compose() {
    docker --context "$DOCKER_CONTEXT" compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() {
    docker-compose --context "$DOCKER_CONTEXT" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  }
else
  echo "Docker Compose is not installed. Install Docker Desktop with Compose v2 enabled." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Create it from .env.development.example first." >&2
  exit 1
fi

action="${1:-up}"
shift || true

case "$action" in
  up)
    compose up --build --remove-orphans "$@"
    ;;
  start)
    compose up -d --build --remove-orphans "$@"
    ;;
  down)
    compose down "$@"
    ;;
  restart)
    compose down
    compose up -d --build --remove-orphans "$@"
    ;;
  status|ps)
    compose ps "$@"
    ;;
  logs)
    compose logs -f "$@"
    ;;
  build)
    compose build "$@"
    ;;
  exec)
    service="${1:?Usage: dev_docker.sh exec SERVICE COMMAND...}"
    shift
    compose exec "$service" "$@"
    ;;
  run)
    compose run --rm "$@"
    ;;
  *)
    echo "Usage: $0 {up|start|down|restart|status|logs|build|exec|run} [args...]" >&2
    exit 2
    ;;
esac
