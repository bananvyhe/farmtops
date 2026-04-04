# ADR 0001: Renderer Choice

## Status

Accepted

## Context

Для игрового мира нужен 2D-рендер с большим количеством спрайтов, тайлов, entity layers и простых эффектов.

Проект уже использует Vue для основного UI. Дополнительно пользователь явно зафиксировал:

- PixiJS + Vue
- GSAP только для UI и transitions

## Decision

Игровой мир рендерится на PixiJS.

Vue остается слоем приложения и HUD. GSAP используется только вне world render loop:

- экранные переходы;
- панели;
- onboarding;
- микровзаимодействия UI.

## Rationale

- PixiJS лучше подходит для sprite-heavy 2D world rendering, чем DOM/CSS.
- Он естественно укладывается в pixel-art pipeline.
- Он проще и легче, чем уходить в полноценный game engine на первой итерации.
- Разделение `Vue for app`, `Pixi for world`, `GSAP for UI motion` удерживает архитектуру чистой.

## Consequences

- Игровая сцена живет отдельно от обычных Vue-компонентов.
- Нужно спроектировать bridge между shard snapshot и Pixi entity graph.
- Нельзя раздувать GSAP до ответственности за анимацию мира.
