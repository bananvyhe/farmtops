# Project checklist

Этот файл фиксирует короткие правила сопровождения проекта. Подробный operational workflow находится в [Development workflow](DEVELOPMENT.md).

## Окружения

- Dev: Docker Compose, все сервисы в контейнерах.
- Production/VPS: Docker Compose, отдельные `web`, `sidekiq`, `postgres`, `redis` и frontend nginx.
- Native Ruby/Node/PostgreSQL/Redis запуск не является поддерживаемым основным dev-сценарием.

## Изменения

- Перед изменением прочитать узкий контекст из [docs/index.md](index.md) и связанного раздела.
- Не смешивать изменения приложения, инфраструктуры и документации без необходимости.
- При изменении env-переменной обновить `.env.development.example` и связанные документы.
- При изменении Gemfile/package-lock или Dockerfile выполнить `up --build`.
- Секреты не добавлять в git; использовать `.env.development` локально и `.env.production` на VPS.

## Проверка перед передачей

```bash
docker compose -f docker-compose.dev.yml config
docker compose -f docker-compose.dev.yml run --rm web bundle exec rails test
docker compose -f docker-compose.dev.yml run --rm frontend npm run build
```

Если Docker engine недоступен, выполнить статическую проверку `docker compose ... config` и явно указать, что runtime smoke test не пройден.

## Фоновые jobs

- Redis и Sidekiq обязательны для dev-потока.
- Sidekiq запускается отдельным контейнером.
- Проверять worker через `docker compose logs -f sidekiq`.
- News translation и game identification используют host-to-container адреса и могут требовать доступ к внешним tunnel-сервисам.

## Безопасность

- Production secrets хранятся вне репозитория.
- После изменения Rails credentials app-контейнеры нужно пересобрать.
- `docker compose down -v` использовать только для осознанного удаления локальных dev-данных.
