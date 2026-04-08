# Architecture

## Текущая база

Сейчас репозиторий содержит:

- Rails API;
- Vue 3 frontend;
- сущности пользователей, платежей, игр, новостей и подписок на игры;
- интеграцию с AI-сервисом для определения игр по новостям.

Игровой слой пока отсутствует.

## Целевая архитектура

Проект расширяется до четырех основных контуров.

### 1. Catalog Context

Отвечает за:

- список игр;
- карточки игр и новости;
- подписки пользователей на игры;
- счетчик followers.

Это уже существует и остается входной воронкой для world shards.

### 2. Matchmaking Context

Отвечает за:

- prime grid пользователя;
- расписание prime simulation;
- расчет групп по пересечению прайм-часов;
- отложенный запуск шарда;
- определение состава участников;
- фиксацию успешного overlap праймов и bot participation.

### 3. World Context

Отвечает за:

- shard lifecycle;
- seed и конфиг генерации;
- карту;
- спавны игроков;
- мобов, босса, ресурсы, расходники;
- server-side bot runtime;
- authoritative combat and gathering resolution;
- respawn timers;
- результаты сессии и farm logs.

### 4. Progression Context

Отвечает за:

- XP и уровни;
- баланс ресурсов;
- энергию;
- добычу уникального shard resource;
- боевые коэффициенты;
- награды за убийство босса.

## Основные компоненты

### Rails API

Авторитативный слой для:

- состояния шарда;
- боевых расчетов;
- экономики;
- серверной симуляции mobs/resources/player avatars;
- хранения прайм-сетки;
- матчмейкинга;
- оркестрации генерации контента;
- интеграции с AI-воркерами.

### Sidekiq Jobs

Фоновый слой для:

- создания шарда по расписанию или при готовности группы;
- генерации названий и описаний контента;
- запроса pixel-art ассетов через tunnel;
- симуляции world tick loop и bot runtime без зависимости от клиента;
- запуска prime-based bot simulation;
- расчета respawn, drops и farm logs;
- ретраев внешних AI-вызовов.

### Vue + PixiJS Client

Клиентский слой разделяется на:

- обычный UI на Vue;
- игровую сцену на PixiJS как renderer-only слой;
- GSAP только для экранных переходов, панелей, раскрытий, onboarding и non-world UI.

## Принципы

- Backend authoritative.
- Client does not own combat, loot or respawn rules.
- Deterministic world seed wherever possible.
- Heavy generation async with caching.
- Game-specific flavor through existing AI infrastructure, not hardcoded tables.
- Watcher-first interaction model.
- Узкий контекст документов и разработки по подсистемам.

## Предлагаемое расширение модели данных

Минимально потребуются новые сущности:

- `user_prime_slots`
- `game_shards`
- `shard_memberships`
- `shard_presence_events`
- `shard_maps`
- `shard_nodes`
- `shard_mobs`
- `shard_bosses`
- `shard_resources`
- `shard_loot_drops`
- `player_shard_progress`
- `bot_runs`

## Предлагаемое поэтапное внедрение

### Phase 1

- перестроить документацию;
- добавить prime grid в профиль;
- ввести серверные сущности для shard и membership;
- показать CTA `Войти в мир` на играх с followers > 0.

### Phase 2

- добавить matchmaking по prime grid;
- реализовать базовый shard lifecycle;
- сгенерировать текстовый world seed и системные параметры;
- запустить server-side simulation loop без зависимости от Vue/Pixi.

### Phase 3

- подключить PixiJS сцену как визуальный клиент к snapshot API;
- реализовать карту, точки спавна, мобов, босса и ресурсы на backend;
- включить bot runtime, progression, respawn и farm logs.

### Phase 4

- подключить AI-генерацию asset pack;
- настроить баланс шардов, длительность 2-5 часов и групповое убийство босса.
