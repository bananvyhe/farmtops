#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_HOST="${DEPLOY_HOST:-root@81.163.29.109}"
REMOTE_PATH="${DEPLOY_PATH:-/srv/farmspot}"
ENV_FILE="${DEPLOY_ENV_FILE:-.env.production}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/farmspot_vps_ed25519}"
SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)

if [ "$#" -gt 0 ]; then
  SERVICES=("$@")
else
  SERVICES=(web sidekiq frontend)
fi

needs_rails_restart=0
for service in "${SERVICES[@]}"; do
  if [ "$service" = "web" ] || [ "$service" = "sidekiq" ]; then
    needs_rails_restart=1
  fi
done

if [ "$needs_rails_restart" -eq 1 ]; then
  for service in "${SERVICES[@]}"; do
    case "$service" in
      web|sidekiq|frontend)
        ;;
      *)
        echo "Unknown service: $service" >&2
        exit 1
        ;;
    esac
  done

  for required_service in web sidekiq frontend; do
    if [[ ! " ${SERVICES[*]} " =~ " ${required_service} " ]]; then
      SERVICES+=("$required_service")
    fi
  done
fi

if [ "${#SERVICES[@]}" -eq 0 ]; then
  echo "No services selected." >&2
  exit 1
fi

echo "Deploy host: $REMOTE_HOST"
echo "Deploy path: $REMOTE_PATH"
echo "Services: ${SERVICES[*]}"

BUILD_SERVICES=()
for service in "${SERVICES[@]}"; do
  case "$service" in
    web|sidekiq)
      if [[ ! " ${BUILD_SERVICES[*]} " =~ " ${service} " ]]; then
        BUILD_SERVICES+=("$service")
      fi
      ;;
    frontend)
      if [[ ! " ${BUILD_SERVICES[*]} " =~ " frontend " ]]; then
        BUILD_SERVICES+=(frontend)
      fi
      ;;
    *)
      echo "Unknown service: $service" >&2
      exit 1
      ;;
  esac
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Preparing remote directory"
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "mkdir -p '$REMOTE_PATH'"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading application files"
tar \
  --exclude='.git' \
  --exclude='.dev' \
  --exclude='log/*' \
  --exclude='tmp/*' \
  --exclude='frontend/node_modules' \
  --exclude='frontend/dist' \
  --exclude='config/master.key' \
  --exclude='.env*' \
  -czf - -C "$ROOT_DIR" . | ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "tar -xzf - -C '$REMOTE_PATH'"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading encrypted credentials"
scp "${SSH_OPTS[@]}" "$ROOT_DIR/config/credentials.yml.enc" "$REMOTE_HOST:$REMOTE_PATH/config/credentials.yml.enc"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Building images one at a time: ${BUILD_SERVICES[*]}"
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "cd '$REMOTE_PATH' && COMPOSE_PARALLEL_LIMIT=1 docker compose --progress plain --env-file '$ENV_FILE' -f docker-compose.prod.yml build ${BUILD_SERVICES[*]}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting services: ${SERVICES[*]}"
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "cd '$REMOTE_PATH' && docker compose --env-file '$ENV_FILE' -f docker-compose.prod.yml up -d --no-build ${SERVICES[*]}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploy completed."
