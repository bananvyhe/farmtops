# Farmspot Docs Index

Цель этой структуры: держать контекст узким. При работе с конкретным разделом сайта или игровой подсистемой сначала открывается только этот индекс, затем только нужная ветка.

## Как читать

- `00-core` содержит продуктовую рамку: зачем проект, общий словарь, архитектурные границы и ключевые решения.
- `10-systems` содержит игровые системы: генерация мира, бой, ресурсы, боссы, лут, прогрессия.
- `20-implementation` содержит прикладную реализацию: API, схема данных, фронтенд, синхронизация, состояние, интеграции.

## 00-core

- [vision.md](/Users/rufus/workspace/projects/farmspot/docs/vision.md)
  Продуктовое видение Farmspot как async-coop auto-farm game поверх каталога игр и подписок.
- [glossary.md](/Users/rufus/workspace/projects/farmspot/docs/glossary.md)
  Единый словарь терминов: шард, прайм, вход в мир, уникальный ресурс, энергия, мировой босс.
- [architecture.md](/Users/rufus/workspace/projects/farmspot/docs/architecture.md)
  Целевые bounded contexts, основные сервисы и поэтапное расширение текущего Rails + Vue проекта.
- [decisions/0001-renderer-choice.md](/Users/rufus/workspace/projects/farmspot/docs/decisions/0001-renderer-choice.md)
  Почему рендер мира строится на PixiJS, а GSAP ограничивается UI и переходами.

## 10-systems

- [worldgen/overview.md](/Users/rufus/workspace/projects/farmspot/docs/worldgen/overview.md)
  Процедурная генерация шардов, карты, спавнов игроков, мобов, босса, ресурсов и pixel-art ассетов.
- [gameplay/combat.md](/Users/rufus/workspace/projects/farmspot/docs/gameplay/combat.md)
  Боевая модель, scaling по числу игроков, XP-кривая, бот-симуляция и условия победы в шарде.
- [gameplay/resources.md](/Users/rufus/workspace/projects/farmspot/docs/gameplay/resources.md)
  Энергия, глобальные и шардовые ресурсы, восстановление HP, лут и tempo 2-5 часовой сессии.

## 20-implementation

- [netcode/overview.md](/Users/rufus/workspace/projects/farmspot/docs/netcode/overview.md)
  Реализация shard lifecycle, presence, prime-time matching, sync loop, authoritative backend и клиентское состояние.
- [runbooks/news_translation.md](/Users/rufus/workspace/projects/farmspot/docs/runbooks/news_translation.md)
  Короткий runbook по очереди перевода новостей, повторным job'ам, lock/recovery и проверке окружения Sidekiq.

## Рекомендуемый узкий вход по задачам

- Если задача про общий смысл продукта: открыть [vision.md](/Users/rufus/workspace/projects/farmspot/docs/vision.md) и [glossary.md](/Users/rufus/workspace/projects/farmspot/docs/glossary.md).
- Если задача про генерацию мира и контент: открыть [worldgen/overview.md](/Users/rufus/workspace/projects/farmspot/docs/worldgen/overview.md).
- Если задача про баланс, XP, мобов и босса: открыть [gameplay/combat.md](/Users/rufus/workspace/projects/farmspot/docs/gameplay/combat.md) и [gameplay/resources.md](/Users/rufus/workspace/projects/farmspot/docs/gameplay/resources.md).
- Если задача про API, БД, presence, синхронизацию и прайм-сетку: открыть [architecture.md](/Users/rufus/workspace/projects/farmspot/docs/architecture.md) и [netcode/overview.md](/Users/rufus/workspace/projects/farmspot/docs/netcode/overview.md).

## Текущий статус репозитория

- Сейчас в коде уже есть Rails API, Vue frontend, каталог игр, идентификация игр через существующую нейро-инфраструктуру и счетчик подписчиков на игру.
- Игровой слой с шардом, прайм-сеткой пользователя, world join, PixiJS-сценой, ботами, боевой системой и ресурсной экономикой еще не реализован.
- Эти документы описывают целевую структуру, чтобы дальнейшая реализация шла по подсистемам, а не одним большим контекстом.
