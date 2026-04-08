# Asset Prompts

## Цель

Этот документ фиксирует, что именно нужно генерировать для мира, какие плейсхолдеры нужны до готовности пайплайна и какие промты держать рядом, чтобы не терять контекст при очередной итерации.

## Что нужно генерировать

### World tiles

- grass tile
- dirt tile
- stone tile
- water tile
- boss arena tile
- edge/cliff tile

### Player and bot sprites

- idle
- walk 4 directions
- attack
- pickup
- hit
- death

### Mob sprites

- common melee mob
- ranged mob
- elite mob
- miniboss
- boss

### Resource and loot sprites

- energy crystal
- healing herb / potion
- shard ore
- rare shard resource
- boss drop

### UI icons

- XP bar icon
- HP icon
- energy icon
- inventory icon
- shard tab icon
- layer occupancy icon

## Общие требования к ассетам

- pixel art;
- dark fantasy / game board mood;
- readable silhouette at small sizes;
- limited palette 8-16 colors;
- consistent outline weight;
- animation frames should align on a stable grid;
- no photorealism;
- no glossy UI chrome.

## Рекомендуемый prompt skeleton

### Tileset prompt

```text
Create a top-down pixel art tileset for a dark cooperative shard game.
Need: grass, dirt, stone, water, boss arena, cliff edge.
Style: readable at 32px, 8-16 color palette, subtle contrast, no photorealism.
Output: separated tiles on transparent background, consistent outline thickness, game-ready.
```

### Player sprite prompt

```text
Create a top-down pixel art player sprite for a cooperative auto-farm game.
Need animation frames: idle, walk, attack, pickup, hit, death.
Style: dark fantasy, small readable silhouette, 8-16 color palette, transparent background.
The character should feel like a bot-controlled observer who farms and fights automatically.
```

### Mob prompt

```text
Create a set of top-down pixel art enemy sprites for a shard-based cooperative game.
Need common mob, elite mob, miniboss, and boss silhouette variants.
Style: hostile, readable at small size, palette-limited, transparent background, no background scene.
Each sprite should be usable as an individual enemy token in a tactical world view.
```

### Resource prompt

```text
Create top-down pixel art resource nodes and loot pickups for a cooperative shard game.
Need energy crystal, healing herb, shard ore, rare shard resource, boss drop.
Style: game readable, glowing accents, limited palette, transparent background.
Each item should be instantly readable on a dark world map.
```

### UI icon prompt

```text
Create a pixel art UI icon set for a dark game interface.
Need icons for XP, HP, energy, inventory, shard tab, layer occupancy.
Style: minimal, consistent stroke, readable at 16-24px, palette limited, transparent background.
```

## Negative prompt suggestions

- no text
- no watermark
- no realistic lighting
- no complex background
- no UI mockup
- no 3D render
- no blur
- no glow bloom overload
- no perspective camera

## Naming contract

To keep the pipeline simple, generated assets should use stable keys:

- `tile_grass`
- `tile_dirt`
- `tile_stone`
- `tile_water`
- `tile_boss_arena`
- `player_idle`
- `player_walk`
- `mob_common`
- `mob_elite`
- `boss_main`
- `resource_energy`
- `resource_heal`
- `resource_shard`
- `ui_xp`
- `ui_hp`
- `ui_energy`

## Restrictions and risks

- Do not couple gameplay logic to the current placeholder art.
- Keep sprite names stable even if the visual style changes.
- If the generator output changes palette or frame count, update only the asset adapter, not world simulation.
- Avoid generating fully detailed background scenes; the game needs token-like clarity first.
