# Netcode Overview

## Цель

Дать ощущение живого совместного шарда без превращения проекта в full real-time action netcode.

Первая версия должна быть near-real-time, но серверно-авторитативной и tolerant к лагам.

## Подход

- Rails API хранит и подтверждает состояние.
- Клиент получает snapshot и delta updates.
- Боевые и экономические расчеты выполняются на backend или worker side.
- PixiJS отображает состояние и локально интерполирует перемещения и UI.

## Что синхронизируется

- shard lifecycle;
- shard layers and layer occupancy;
- список участников;
- presence events;
- позиции игроков и bot avatars;
- состояние мобов и босса;
- resource nodes и pickups;
- XP bank, HP, энергия и ключевые статусы.

## Prime grid и matchmaking

Пользователь в профиле получает удобную почасовую сетку.

Требования к UX:

- клик по часу переключает слот;
- drag по диапазону часов красит несколько слотов;
- отдельный быстрый action для рабочих дней и выходных;
- сохраняется в UTC или в нормализованном локальном часовом поясе с явной конверсией.

Смысл prime grid:

- это расписание для bot runtime;
- в эти часы персонаж должен автоматически участвовать в симуляции;
- реальный вход пользователя не обязателен;
- совпадение праймов нескольких пользователей должно переводить ботов из разрозненного фарма в совместное движение к цели.

Матчмейкинг использует:

- followers у игры;
- overlap прайм-часов;
- фактические недавние входы;
- допустимый размер группы.

## Авторитативный цикл

Практичный старт:

- client poll или lightweight subscription каждые 1-3 секунды;
- background simulation ticks на backend;
- отдельный lock на активный shard tick;
- snapshot versioning для идемпотентного обновления клиента.

Если later-stage нагрузка вырастет, этот контур можно вынести в отдельный realtime service, но для первой версии это преждевременное усложнение.

## API-контракты, которые понадобятся

- `GET /api/profile/prime-grid`
- `PUT /api/profile/prime-grid`
- `POST /api/games/:id/world-entry`
- `GET /api/shards/:id`
- `GET /api/shards/:id/layers`
- `GET /api/shards/:id/snapshot`
- `POST /api/shards/:id/presence`
- `POST /api/shards/:id/actions`
- `GET /api/shards/:id/result`

## Состояние на клиенте

UI state стоит держать в слоях:

- session and profile state;
- catalog and game page state;
- shard lobby state;
- active shard runtime state;
- Pixi entity cache and render adapters.

В UI важно показывать watcher-сигналы:

- кто еще ищет эту игру;
- когда бот персонажа войдет в активную симуляцию;
- началось ли движение нескольких персонажей к общей цели;
- как растет групповой прогресс.

Это позволит открывать для работы только нужный слой контекста.
