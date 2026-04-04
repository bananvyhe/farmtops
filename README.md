# Farmspot

Карта документации с узким входом по подсистемам:
`/Users/rufus/workspace/projects/farmspot/docs/index.md`

Rails 8 приложение с:

- Rails API как backend
- frontend на `Vue 3 Composition API`
- ролями `admin`, `user`, `client`
- кабинетом клиента с балансом и расчётом оставшихся дней
- пополнением через YooMoney
- Vue-админкой со списком пользователей, тарифами и новостными источниками
- почасовым списанием средств через `Sidekiq`
- расписанием периодических задач через `sidekiq-cron`
- импортом пользователей из CSV

## Frontend UI

Правила по Vuetify, теме и UI-конвенциям:
`/Users/rufus/workspace/projects/farmspot/docs/vuetify.md`

## Запуск

1. Выполнить `bundle install`.
2. Выполнить `cd frontend && npm install`.
3. Поднять локальные PostgreSQL и Redis:
   `./scripts/dev_services_up.sh`
4. Выполнить `bundle exec rails db:prepare`.
5. При необходимости создать админа:
   `ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=secret bundle exec rails db:seed`
6. Запустить Rails API:
   `bundle exec rails server -b 127.0.0.1 -p 3000`
7. Запустить Vue frontend:
   `cd frontend && npm run dev -- --host 127.0.0.1`
8. Запустить воркер (он же планировщик):
   `bundle exec sidekiq -C config/sidekiq.yml`
   - В dev можно ускорить списания, задав `BILLING_INTERVAL_MINUTES=3`
9. Однократно прогнать краул текущих источников:
   `./scripts/news_crawl_once.sh`

Либо поднять dev-сервисы одной командой:

```bash
./scripts/dev_up.sh
```

## Production / VPS

Для продового деплоя подготовлен docker stack в [docker-compose.prod.yml](/Users/rufus/workspace/projects/farmspot/docker-compose.prod.yml):

- `postgres`
- `redis`
- `web` (`Rails + Puma`)
- `sidekiq`
- `frontend` (`Nginx` со статическим Vue build и proxy на Rails API)

Под домен `https://farmspot.ru` нужен файл окружения:

```bash
cp .env.production.example .env.production
```

Дальше заполнить секреты в `.env.production` и запустить:

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

Frontend-контейнер слушает `127.0.0.1:8080` по умолчанию и предназначен для внешнего reverse proxy на VPS.
Для отдельного контура `farmspot.ru` можно использовать `127.0.0.1:8082`, чтобы не конфликтовать с другими сайтами на том же сервере.
Если у вас уже есть общий Nginx/Caddy/Traefik на сервере, его нужно направить на нужный локальный порт frontend-контейнера для домена `farmspot.ru`.
При первом старте `web` контейнер автоматически подхватит источники новостей из `sites.txt`, если база ещё пустая.

Для краула и перевода на Linux в Docker Compose контейнер должен видеть хостовый tunnel через `host.docker.internal`:

- добавьте `extra_hosts: ["host.docker.internal:host-gateway"]` для `web` и `sidekiq`
- задайте `NEWS_TRANSLATOR_BASE_URL=http://host.docker.internal:19191`
- если переводчик обрабатывает одну статью долго, увеличьте `NEWS_TRANSLATOR_READ_TIMEOUT_SECONDS` до значения, которое покрывает один перевод
- для идентификации игр можно использовать тот же туннель и те же креды, что у переводчика: если `NEWS_GAME_ID_BASE_URL` / `NEWS_GAME_ID_TOKEN` не заданы, клиент и smoke-скрипт берут `NEWS_TRANSLATOR_BASE_URL` / `NEWS_TRANSLATOR_TOKEN`
- если game-id сервис держит запрос дольше обычного, увеличьте `NEWS_GAME_ID_READ_TIMEOUT_SECONDS`
- перевод новостей идет цепочкой из одной статьи за раз: crawl сначала сохраняет оригинал, затем `NewsTranslatePendingArticlesJob` и `NewsTranslateArticleJob` по очереди обрабатывают статьи
- если reverse tunnel слушает только `127.0.0.1` на VPS, контейнер его не увидит; туннель должен быть доступен с хоста или через отдельный прокси
- если из контейнера `curl http://host.docker.internal:19191/health` висит на timeout, проверьте UFW на VPS: Docker bridge трафик до `19191/tcp` должен быть разрешен, например `ufw allow from 172.16.0.0/12 to any port 19191 proto tcp`
- на VPS в `sshd` нужно включить `GatewayPorts clientspecified`
- клиент туннеля должен стартовать с `-RemoteBindAddress 0.0.0.0`
- если tunnel уже поднят на хосте, проверка из контейнера выглядит так:

```bash
curl http://host.docker.internal:19191/health
```

Если меняете порт туннеля, синхронно обновляйте:

- `.env.production` на VPS
- `docker-compose.prod.yml`
- локальный/удаленный запуск reverse tunnel
- затем пересобирайте и перезапускайте `web` и `sidekiq`

Быстрый деплой ваших изменений с локальной машины:

```bash
./scripts/deploy_prod.sh
```

Для отдельного farmspot-контейнера на VPS:

```bash
./scripts/deploy_farmspot_prod.sh
```

Можно деплоить только часть сервисов:

```bash
./scripts/deploy_prod.sh web sidekiq
```

Скрипт:

- копирует проект в `/srv/farmspot`
- синхронизирует `config/credentials.yml.enc`
- не копирует `config/master.key` и `.env.production`
- запускает `docker compose ... up -d --build`

`deploy_farmspot_prod.sh` использует тот же поток, но по умолчанию фиксирует отдельный frontend-порт `127.0.0.1:8082`.

### Production Caveats

- `Rails credentials` в этом проекте baked into Docker image.
- После любого изменения `config/credentials.yml.enc` недостаточно `restart`.
- Нужно пересобирать контейнеры:

```bash
./scripts/deploy_prod.sh web sidekiq
```

- `Sidekiq Web` использует отдельный basic auth из `credentials.sidekiq.*`.
- Это не логин пользователя сайта.
- Канонический URL панели: `https://farmspot.ru/sidekiq/`
- Перевод новостей работает как цепочка из одной статьи за раз: `NewsTranslatePendingArticlesJob` стартует lock-guarded chain, `NewsTranslateArticleJob` переводит одну статью, сохраняет результат и только потом ставит следующую.
- При старте `Sidekiq` автоматически запускается recovery очереди перевода: очищается stale `news:translation:pending_articles_lock`, свежие `failed`/stalled `translating` новости переводятся обратно в `pending`, затем снова ставится `NewsTranslatePendingArticlesJob`.
- Вручную это можно запустить через `bundle exec rake news:translation:recover`.
- Это не callback-based async протокол: translator остаётся внешним sync HTTP сервисом, поэтому `NEWS_TRANSLATOR_READ_TIMEOUT_SECONDS` всё ещё важен для одного перевода.
- После завершения перевода всех статей автоматически стартует следующий этап: `NewsIdentifyPendingGamesJob` отправляет `body_text` в game-id сервис и сохраняет результат в `games` / `news_article_games`.
- Для ручной проверки одной статьи используйте `bash scripts/news_game_identify_sample.sh ARTICLE_ID [source|translated]`.
- Нулевая статистика списаний не всегда значит, что планировщик сломан:
  часто у пользователей просто `hourly_rate_cents = 0` и нет назначенного тарифа.
- После импорта пользователей из старого проекта нужно отдельно проверить:
  - назначены ли тарифы
  - есть ли ненулевая почасовая ставка
  - есть ли записи `hourly_charge` в `balance_ledger_entries`

## Переменные окружения

- `JWT_SIGNING_KEY` или `credentials.jwt.signing_key`
- `REDIS_URL` или `credentials.redis.url`
- `APP_BASE_URL` для `successURL` YooMoney
- `YOOMONEY_RECEIVER` или `credentials.yoomoney.receiver`
- `YOOMONEY_NOTIFICATION_SECRET` или `credentials.yoomoney.notification_secret`
- `SIDEKIQ_WEB_USERNAME` или `credentials.sidekiq.web_username`
- `SIDEKIQ_WEB_PASSWORD` или `credentials.sidekiq.web_password`
- `NEWS_CRAWL_INTERVAL_HOURS` для интервала краула новостей
- `NEWS_CRAWL_MIN_DELAY_SECONDS` и `NEWS_CRAWL_MAX_DELAY_SECONDS` для polite crawl pacing
- `NEWS_GAME_ID_BASE_URL` и `NEWS_GAME_ID_TOKEN` для game-id сервиса, с fallback на `NEWS_TRANSLATOR_BASE_URL` и `NEWS_TRANSLATOR_TOKEN`
- `NEWS_GAME_ID_READ_TIMEOUT_SECONDS` и `NEWS_GAME_ID_OPEN_TIMEOUT_SECONDS` для game-id сервиса
- `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` или `credentials.postgres.*`

Секреты лучше хранить в `Rails credentials`:

```bash
EDITOR=nano bin/rails credentials:edit
```

Пример структуры:

```yml
jwt:
  signing_key: "..."

postgres:
  host: "127.0.0.1"
  port: 5432
  username: "rufus"
  password: ""
  development_database: "farmspot_development"
  test_database: "farmspot_test"
  production_database: "farmspot_production"

redis:
  host: "127.0.0.1"
  port: 6379
  db: 0
  password: ""
  url: ""

yoomoney:
  receiver: "..."
  notification_secret: "..."
sidekiq:
  web_username: "admin"
  web_password: "CHANGE_ME_SIDEKIQ_PASSWORD"
app:
  base_url: "http://127.0.0.1:3000"
```

`config/master.key` нельзя коммитить в репозиторий.
На сервер `master key` передаётся через `RAILS_MASTER_KEY` в `.env.production`, а не отдельным файлом.

## Импорт пользователей

CSV запускается так:

```bash
bundle exec rake users:import CSV=tmp/users.csv
```

Импорт из старой базы Farmspot:

```bash
OLD_DATABASE_URL=postgres://USER:PASS@HOST:5432/DBNAME bundle exec rake users:import_farmspot
```

Если база доступна только на VPS, можно использовать SSH-туннель:

```bash
ssh -L 55432:127.0.0.1:5432 USER@YOUR_VPS
OLD_DATABASE_URL=postgres://USER:PASS@127.0.0.1:55432/DBNAME bundle exec rake users:import_farmspot
```

Импорт списка URL для новостей:

```bash
bundle exec rake news:import_sites FILE=sites.txt
```

Одноразовый запуск краула по текущей настройке:

```bash
./scripts/news_crawl_once.sh
```

Поддерживаемые поля:

- `email`
- `password`
- `role`
- `hourly_rate_cents`
- `balance_cents`
- `active`
- `external_id`
- `source`
# blank_repo
