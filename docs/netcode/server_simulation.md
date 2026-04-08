# Server Simulation

Этот документ фиксирует целевую модель игры: мир существует и обновляется на сервере, а клиент только рисует подтвержденное состояние.

## Базовый принцип

- Server authoritative.
- Vue + PixiJS не должны принимать решения о смерти, добыче, респауне, спавне или наградах.
- Если frontend выключен, shard simulation все равно продолжается.
- Если frontend запущен, он лишь отображает текущий snapshot и анимации поверх него.

## Что должно жить на сервере

- spawn игроков на карту только в активные prime slots;
- despawn игроков вне прайма;
- spawn mobs и resources в детерминированных координатах по seed;
- patrol, combat, death, loot drop и respawn;
- resource gathering и inventory gain;
- boss progression, HP pool и unlock timing;
- farm logs и session summaries;
- shard layer occupancy и auto migration to free layer if needed.

## Что должен отдавать snapshot

- `world.seed`
- `world.mode`
- `world.current_week_slot_utc`
- `world.active_players_count`
- `world.players`
- `world.mobs`
- `world.resources`
- `world.drops`
- `world.boss`
- `world.inventory`
- `world.farm_log`
- `world.progress`

## Player lifecycle

1. Сервер проверяет prime slot пользователя.
2. Если слот активен, пользователь получает active player avatar в shard snapshot.
3. Автосимуляция двигает avatar по маршруту фарма.
4. При контакте с mob сервер фиксирует бой, исчезновение mob, drop и damage.
5. При контакте с resource сервер фиксирует gather, исчезновение node и inventory gain.
6. После respawn timeout entity появляется заново в той же логической точке.

## Entity rules

### Mob

- Mob не исчезает сам.
- Mob может исчезнуть только после server-side combat resolution.
- После смерти mob оставляет drop.
- Respawn timeout по умолчанию равен 60 секундам, если не переопределено seed-правилом шарда.

### Resource

- Resource не исчезает сам.
- Resource может исчезнуть только после server-side gather resolution.
- При сборе ресурс сразу дает энергию, healing или shard ore.
- Respawn timeout по умолчанию равен 60 секундам.

### Player avatar

- Player avatar существует только если прайм-слот активен.
- Вне прайма avatar не должен присутствовать в active world snapshot.
- Никнейм всегда приходит с сервера и отображается над моделькой.

## Client contract

- Клиент получает только подтвержденный snapshot.
- Клиент может сглаживать движение и показывать hit/gather animations.
- Клиент не имеет права быть источником truth для world state.

## Implementation order

1. Вынести текущую pseudo-simulation из Vue в backend services.
2. Сделать server tick loop и snapshot persistence.
3. Добавить entity state machine для mobs/resources/drops.
4. Подключить farm logs и session summaries.
5. Оставить PixiJS только как renderer of server state.

