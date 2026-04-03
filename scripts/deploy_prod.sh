#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_HOST="${DEPLOY_HOST:-root@81.163.29.109}"
REMOTE_PATH="${DEPLOY_PATH:-/srv/farmspot}"
ENV_FILE="${DEPLOY_ENV_FILE:-.env.production}"

if [ "$#" -gt 0 ]; then
  SERVICES=("$@")
else
  SERVICES=(web sidekiq frontend)
fi

needs_frontend_restart=0
for service in "${SERVICES[@]}"; do
  if [ "$service" = "web" ] || [ "$service" = "sidekiq" ]; then
    needs_frontend_restart=1
  fi
done

if [ "$needs_frontend_restart" -eq 1 ]; then
  has_frontend=0
  for service in "${SERVICES[@]}"; do
    if [ "$service" = "frontend" ]; then
      has_frontend=1
      break
    fi
  done

  if [ "$has_frontend" -eq 0 ]; then
    SERVICES+=(frontend)
  fi
fi

echo "Deploy host: $REMOTE_HOST"
echo "Deploy path: $REMOTE_PATH"
echo "Services: ${SERVICES[*]}"

ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_PATH'"

tar \
  --exclude='.git' \
  --exclude='.dev' \
  --exclude='log/*' \
  --exclude='tmp/*' \
  --exclude='frontend/node_modules' \
  --exclude='frontend/dist' \
  --exclude='config/master.key' \
  --exclude='.env*' \
  -czf - -C "$ROOT_DIR" . | ssh "$REMOTE_HOST" "tar -xzf - -C '$REMOTE_PATH'"

scp "$ROOT_DIR/config/credentials.yml.enc" "$REMOTE_HOST:$REMOTE_PATH/config/credentials.yml.enc"

ssh "$REMOTE_HOST" "cd '$REMOTE_PATH' && docker compose --env-file '$ENV_FILE' -f docker-compose.prod.yml up -d --build ${SERVICES[*]}"

echo "Deploy completed."
