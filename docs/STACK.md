# Stack и окружения

## Канонический режим разработки

Разработка запускается через Docker Compose. Все сервисы проекта работают в контейнерах:

- `postgres` — PostgreSQL 16;
- `redis` — Redis 7;
- `web` — Rails 8 API в development mode;
- `sidekiq` — фоновые jobs;
- `frontend` — Vite/Vue 3 на Node 20.

Dev-образы содержат исходный код проекта. Это специально сделано совместимым с WSL и Docker daemon, работающим вне WSL, где bind mount путей `/mnt/c/...` может быть пустым. После изменения Ruby или frontend-кода нужно повторить `up --build`. Gems хранятся в named volume.

Запуск из корня репозитория:

```bash
cp .env.development.example .env.development
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

Приложение доступно по адресам:

- frontend: http://localhost:8082;
- Rails healthcheck: http://localhost:3002/up.

Фоновый worker запускается тем же Compose-проектом. Логи конкретного сервиса: `docker compose -f docker-compose.dev.yml logs -f web`.

Остановка без удаления данных:

```bash
docker compose --env-file .env.development -f docker-compose.dev.yml down
```

Для полного сброса локальных PostgreSQL/Redis данных используется `down -v`. Это удаляет только named volumes dev-проекта и должно выполняться осознанно.

## Production / VPS

Production остается Docker-only и запускается через `docker-compose.prod.yml`. В production используются отдельные Rails и Sidekiq контейнеры, PostgreSQL/Redis volumes и собранный frontend через nginx. Секреты передаются через `.env.production` или окружение VPS; реальные секреты не коммитятся.

## Версии

- Ruby: 3.3.5 (`.ruby-version`);
- Rails: 8.0.4 (`Gemfile.lock`);
- Node: 20 в dev-контейнере и production build;
- PostgreSQL: 16;
- Redis: 7;
- Vite: 5.x.

## Внешние AI-сервисы

По умолчанию Rails-контейнеры обращаются к сервисам на host через `host.docker.internal:19191` и `:19192`. Если эти сервисы не запущены, основное приложение и тесты все равно могут работать; news jobs, которым нужен внешний сервис, будут ждать или завершаться по своей политике retry.
