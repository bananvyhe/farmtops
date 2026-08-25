# Development workflow

## Первый запуск

Требования: Docker Desktop с запущенным Linux engine и Docker Compose v2.

```bash
cp .env.development.example .env.development
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

В Windows PowerShell:

```powershell
Copy-Item .env.development.example .env.development
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

Открыть http://localhost:8082. Готовность Rails проверяется через http://localhost:3002/up.

## WSL-скрипты

Docker должен использовать локальный context `default`, а не VPS context `remote-server`:

```bash
docker context use default
bash scripts/dev_up.sh
```

Основные команды:

```bash
bash scripts/dev_status.sh
bash scripts/dev_docker.sh logs web sidekiq frontend
bash scripts/dev_docker.sh exec web bundle exec rails console
bash scripts/dev_docker.sh exec web bundle exec rails db:migrate
bash scripts/dev_docker.sh run web bundle exec rails test
bash scripts/dev_down.sh
```

Для явного выбора context:

```bash
DOCKER_CONTEXT=default bash scripts/dev_up.sh
DOCKER_CONTEXT=remote-server bash scripts/dev_docker.sh status
```

`remote-server` предназначен для VPS/deploy. Локальный сайт будет доступен только когда dev-контейнеры запущены через `default`.

## Повседневные команды

```bash
# фоновой запуск
docker compose --env-file .env.development -f docker-compose.dev.yml up -d

# статус и логи
docker compose -f docker-compose.dev.yml ps
docker compose -f docker-compose.dev.yml logs -f web sidekiq frontend

# Rails console / миграции / тесты
docker compose -f docker-compose.dev.yml exec web bundle exec rails console
docker compose -f docker-compose.dev.yml exec web bundle exec rails db:migrate
docker compose -f docker-compose.dev.yml run --rm web bundle exec rails test

# frontend checks
docker compose -f docker-compose.dev.yml exec frontend npm run build

# остановка
docker compose --env-file .env.development -f docker-compose.dev.yml down
```

Dev-образы содержат копию исходников, поэтому после изменения Ruby или frontend-кода повторяй `up --build`. При изменении только env-переменных пересборка не нужна.

Dev-контейнеры намеренно не используют Rails production entrypoint: `db:prepare` выполняется непосредственно командой `web`. Исходники запекаются в dev-образы, потому что bind mount `/mnt/c/...` может не передавать файлы Docker daemon при смешанном WSL/Docker Desktop окружении.

## Правила конфигурации

- `.env.development` — только локальные значения, не коммитить.
- `.env.development.example` — список поддерживаемых dev-переменных и безопасные defaults.
- `RAILS_MASTER_KEY` и production secrets не нужны для обычного dev-старта, если заданы dev env-переменные.
- `PGHOST`, `REDIS_URL`, `JWT_SIGNING_KEY` и proxy target frontend должны указывать на имена Compose-сервисов, а не на `localhost` внутри контейнера.
- `localhost` в браузере означает host-машину; `web`, `postgres` и `redis` — адреса только внутри Compose-сети.

## Типовые проблемы

- Docker engine недоступен: запустить Docker Desktop и проверить `docker compose version`.
- Порт занят: задать `WEB_PORT` или `FRONTEND_PORT` в `.env.development`.
- Сломалась локальная база: `docker compose -f docker-compose.dev.yml down -v` и повторить запуск. Команда удаляет dev-данные.
- Sidekiq не стартует: сначала проверить `docker compose -f docker-compose.dev.yml ps` и healthcheck `postgres`/`redis`, затем `logs sidekiq`.
- Host AI service недоступен: проверить адреса `NEWS_TRANSLATOR_BASE_URL` и `NEWS_GAME_ID_BASE_URL`; это не должно мешать запуску Rails/frontend.

## Rails credentials

Не запускай `rails credentials:edit` напрямую из WSL: Ruby и gems проекта находятся в Docker. Используй:

```bash
bash scripts/credentials_edit.sh
```

Для другого редактора: `EDITOR=vim bash scripts/credentials_edit.sh`.
