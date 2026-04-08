<script setup>
import { Application, Container, Graphics } from "pixi.js"
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import { useRoute, RouterLink } from "vue-router"
import { api } from "../api"

const route = useRoute()
const loading = ref(true)
const refreshing = ref(false)
const error = ref("")
const worldResponse = ref(null)
const selectedLayerId = ref(null)
const pixiHostRef = ref(null)
const sceneSummary = ref("")
let frameHandle = null
let refreshHandle = null
let app = null
let stageContainer = null

const shard = computed(() => worldResponse.value?.shard || null)
const layers = computed(() => worldResponse.value?.layers || [])
const world = computed(() => worldResponse.value?.world || null)
const activeLayer = computed(() => layers.value.find((layer) => String(layer.id) === String(selectedLayerId.value)) || null)

function formatDate(value) {
  if (!value) return "—"
  return new Intl.DateTimeFormat("ru-RU", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}

function formatLayerLabel(layer) {
  if (!layer) return "Слой"
  return `Слой ${layer.layer_index}`
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

function hexColor(value) {
  return Number.parseInt(String(value).replace("#", ""), 16)
}

function lerp(from, to, progress) {
  return from + (to - from) * progress
}

function routeProgressFromTimestamp(player, timestamp) {
  const cycleSeconds = Number(player.route_cycle_seconds || 48)
  const routeOffset = Number(player.route_offset_seconds || 0)
  const clock = timestamp / 1000 + routeOffset
  return ((clock % cycleSeconds) + cycleSeconds) % cycleSeconds / cycleSeconds
}

function routePositionAtTimestamp(player, timestamp) {
  const path = Array.isArray(player.path) ? player.path : []
  if (path.length < 2) {
    return {
      x: Number(player.x || 0),
      y: Number(player.y || 0),
      phase: 0,
      action: player.action || "idle"
    }
  }

  const phase = routeProgressFromTimestamp(player, timestamp)
  const segmentCount = path.length - 1
  const segmentFloat = phase * segmentCount
  const segmentIndex = Math.min(segmentCount - 1, Math.floor(segmentFloat))
  const localPhase = segmentFloat - segmentIndex
  const from = path[segmentIndex]
  const to = path[segmentIndex + 1]
  const action = player.action || (segmentIndex === 0 ? "gather" : segmentIndex === 1 ? "fight" : "return")

  return {
    x: lerp(Number(from.x || 0), Number(to.x || 0), localPhase),
    y: lerp(Number(from.y || 0), Number(to.y || 0), localPhase),
    phase,
    action
  }
}

async function enterLayer(layerId = null) {
  const shardId = route.params.id
  refreshing.value = true
  error.value = ""

  try {
    const data = await api.enterShard(shardId, layerId)
    worldResponse.value = data
    selectedLayerId.value = data.joined_layer_id || data.active_layer_id || data.layers?.[0]?.id || null
  } catch (err) {
    error.value = err.message
  } finally {
    refreshing.value = false
  }
}

async function loadWorld() {
  const shardId = route.params.id
  loading.value = true
  error.value = ""

  try {
    const data = await api.shardWorld(shardId)
    worldResponse.value = data
    selectedLayerId.value = data.active_layer_id || data.layers?.[0]?.id || null
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}

async function refreshWorld() {
  if (!route.params.id) return
  if (refreshing.value) return

  try {
    const data = await api.shardWorld(route.params.id)
    worldResponse.value = data
    if (!selectedLayerId.value || !layers.value.some((layer) => String(layer.id) === String(selectedLayerId.value))) {
      selectedLayerId.value = data.active_layer_id || data.layers?.[0]?.id || null
    }
  } catch (err) {
    error.value = err.message
  }
}

async function chooseLayer(layerId) {
  if (String(layerId) === String(selectedLayerId.value)) return
  await enterLayer(layerId)
}

function getWorldMetrics() {
  const grid = world.value?.map
  const gridWidth = Number(grid?.width || 28)
  const gridHeight = Number(grid?.height || 16)
  const tiles = Array.isArray(grid?.tiles) ? grid.tiles : []
  const width = app?.renderer?.width || pixiHostRef.value?.clientWidth || 960
  const height = app?.renderer?.height || pixiHostRef.value?.clientHeight || 560
  const tileSize = Math.max(12, Math.floor(Math.min(width / gridWidth, (height - 24) / gridHeight)))
  const mapWidth = gridWidth * tileSize
  const mapHeight = gridHeight * tileSize
  const offsetX = Math.floor((width - mapWidth) / 2)
  const offsetY = Math.floor((height - mapHeight) / 2)

  return {
    gridWidth,
    gridHeight,
    tiles,
    width,
    height,
    tileSize,
    mapWidth,
    mapHeight,
    offsetX,
    offsetY
  }
}

function drawWorld(timestamp) {
  if (!app || !stageContainer || !world.value) return

  const metrics = getWorldMetrics()
  const { gridWidth, gridHeight, tiles, width, height, tileSize, offsetX, offsetY, mapWidth, mapHeight } = metrics
  const progress = Number(world.value.progress?.boss_unlock_progress || world.value.progress?.group_progress || 0)
  const stage = stageContainer

  stage.removeChildren()

  const background = new Graphics()
  background.rect(0, 0, width, height).fill(hexColor("#0a0d14"))
  stage.addChild(background)

  const aura = new Graphics()
  aura.circle(width / 2, height / 2, Math.min(width, height) * 0.38).fill({ color: hexColor("#121826"), alpha: 0.8 })
  stage.addChild(aura)

  const gridGfx = new Graphics()
  tiles.forEach((row, y) => {
    row.forEach((tile, x) => {
      const px = offsetX + x * tileSize
      const py = offsetY + y * tileSize
      const color =
        tile === "water"
          ? "#123d5c"
          : tile === "stone"
            ? "#525965"
            : tile === "dirt"
              ? "#6d4b2f"
              : tile === "boss"
                ? "#6d1f1f"
                : "#20331f"
      gridGfx.rect(px, py, tileSize, tileSize).fill({ color: hexColor(color), alpha: 1 })
      gridGfx.rect(px, py, tileSize, tileSize).stroke({ width: 1, color: hexColor("#ffffff"), alpha: 0.04 })
    })
  })
  stage.addChild(gridGfx)

  const routeGfx = new Graphics()
  world.value.players.forEach((player) => {
    if (!Array.isArray(player.path) || player.path.length < 2) return
    const points = player.path.map((point) => ({
      x: offsetX + point.x * tileSize + tileSize / 2,
      y: offsetY + point.y * tileSize + tileSize / 2
    }))
    routeGfx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((point) => routeGfx.lineTo(point.x, point.y))
    routeGfx.stroke({ width: 2, color: hexColor("#7dd3fc"), alpha: 0.2 })
  })
  stage.addChild(routeGfx)

  const entities = new Graphics()

  world.value.resources.forEach((resource) => {
    const radius = resource.kind === "shard_ore" ? 8 : 6
    const fill =
      resource.kind === "energy_crystal"
        ? "#83d8ff"
        : resource.kind === "heal_herb"
          ? "#96ef9a"
          : "#d9b065"
    const cx = offsetX + resource.x * tileSize + tileSize / 2
    const cy = offsetY + resource.y * tileSize + tileSize / 2
    entities.circle(cx, cy, radius).fill({ color: hexColor(fill), alpha: 0.98 })
  })

  world.value.drops?.forEach((drop) => {
    const cx = offsetX + drop.x * tileSize + tileSize / 2
    const cy = offsetY + drop.y * tileSize + tileSize / 2
    const fill = drop.rarity === "rare" ? "#f7c86b" : "#c8d0da"
    entities.roundRect(cx - 4, cy - 4, 8, 8, 2).fill({ color: hexColor(fill), alpha: 0.8 })
  })

  world.value.mobs.forEach((mob, index) => {
    const wobble = Math.sin(timestamp / 1000 + index) * 0.4
    const cx = offsetX + mob.x * tileSize + tileSize / 2 + wobble
    const cy = offsetY + mob.y * tileSize + tileSize / 2
    entities.circle(cx, cy, 7 + (mob.level % 2)).fill({ color: hexColor("#ff8858"), alpha: 0.9 })
  })

  world.value.players.forEach((player, index) => {
    const routePoint = routePositionAtTimestamp(player, timestamp)
    const px = routePoint.x
    const py = routePoint.y
    const cx = offsetX + px * tileSize + tileSize / 2
    const cy = offsetY + py * tileSize + tileSize / 2
    const color =
      routePoint.action === "fight"
        ? "#7dd3fc"
        : routePoint.action === "return"
          ? "#c7d2fe"
          : "#ffd18a"
    entities.circle(cx, cy, 10).fill({ color: hexColor(color), alpha: 1 })
    entities.circle(cx, cy, 14).stroke({ width: 1, color: hexColor(color), alpha: 0.24 })
    entities.roundRect(cx - 12, cy - 22, 24, 10, 4).fill({ color: hexColor("#101826"), alpha: 0.9 })
    entities.roundRect(cx - 12, cy - 22, 24 * Math.max(0.15, routePoint.phase), 10, 4).fill({ color: hexColor(color), alpha: 0.95 })
  })

  const boss = world.value.boss
  const bossCx = offsetX + boss.x * tileSize + tileSize / 2
  const bossCy = offsetY + boss.y * tileSize + tileSize / 2 + Math.sin(timestamp / 400) * 2
  entities.circle(bossCx, bossCy, 16 + Math.sin(timestamp / 500) * 2).fill({ color: hexColor("#b93b3b"), alpha: 1 })
  entities.circle(bossCx, bossCy, 22).stroke({ width: 2, color: hexColor("#ffd2d2"), alpha: 0.45 })
  stage.addChild(entities)

  const ui = new Container()
  ui.zIndex = 10
  const progressBarWidth = Math.min(420, width - 32)
  const progressBar = new Graphics()
  progressBar.roundRect(16, 16, progressBarWidth, 16, 8).fill({ color: hexColor("#1c2433"), alpha: 0.9 })
  progressBar.roundRect(16, 16, (progressBarWidth * progress) / 100, 16, 8).fill({ color: hexColor("#c75923"), alpha: 1 })
  ui.addChild(progressBar)

  const meter = new Graphics()
  meter.roundRect(16, 40, Math.min(520, width - 32), 70, 14).fill({ color: hexColor("#111722"), alpha: 0.82 })
  meter.roundRect(16, 40, Math.min(520, width - 32), 70, 14).stroke({ width: 1, color: hexColor("#ffffff"), alpha: 0.08 })
  ui.addChild(meter)

  stage.addChild(ui)

  sceneSummary.value = `boss:${progress}% bank:${world.value.inventory?.banked_xp || 0} pending:${world.value.inventory?.pending_xp || 0}`
  world.value.players.forEach((player) => {
    const routePoint = routePositionAtTimestamp(player, timestamp)
    const cx = offsetX + routePoint.x * tileSize + tileSize / 2
    const cy = offsetY + routePoint.y * tileSize + tileSize / 2
    const marker = new Graphics()
    marker.circle(cx - 12, cy - 12, 2).fill({ color: hexColor("#ffffff"), alpha: 0.65 })
    stage.addChild(marker)
  })
}

function animationLoop(timestamp) {
  drawWorld(timestamp)
  frameHandle = window.requestAnimationFrame(animationLoop)
}

onMounted(async () => {
  app = new Application()
  await app.init({
    background: "#0a0d14",
    resizeTo: pixiHostRef.value,
    antialias: false,
    autoDensity: true,
    resolution: window.devicePixelRatio || 1
  })
  stageContainer = new Container()
  stageContainer.sortableChildren = true
  app.stage.addChild(stageContainer)
  pixiHostRef.value.appendChild(app.canvas)
  await loadWorld()
  await enterLayer(selectedLayerId.value)
  frameHandle = window.requestAnimationFrame(animationLoop)
  refreshHandle = window.setInterval(refreshWorld, 4000)
})

onBeforeUnmount(() => {
  if (frameHandle) window.cancelAnimationFrame(frameHandle)
  if (refreshHandle) window.clearInterval(refreshHandle)
  app?.destroy(true, { children: true, texture: true, context: true })
  app = null
  stageContainer = null
})
</script>

<template>
  <main class="world-page">
    <section class="card world-hero card--dark">
      <div>
        <div class="eyebrow">shard runtime</div>
        <h1>{{ shard ? shard.game_name : "Мир" }}</h1>
        <p class="muted">
          Плейсхолдерная сцена для мира. Сейчас здесь уже есть слои, автозапуск бота, ресурсы и босс, а ассеты потом
          можно заменить на процедурную генерацию.
        </p>
      </div>
      <div class="world-hero__meta">
        <span class="profile-pill">Seed: {{ shard ? shard.world_seed : "—" }}</span>
        <span class="profile-pill">Создан: {{ shard ? formatDate(shard.created_at) : "—" }}</span>
        <span class="profile-pill">Лайер: {{ activeLayer ? formatLayerLabel(activeLayer) : "—" }}</span>
      </div>
    </section>

    <section class="card world-layers card--dark">
      <div class="profile-grid-card__header">
        <div>
          <h2>Слои</h2>
          <p class="muted">На одном слое одновременно может быть не больше 10 активных участников.</p>
        </div>
        <RouterLink to="/profile" class="ghost">Вернуться в профиль</RouterLink>
      </div>

      <v-tabs
        v-if="layers.length"
        v-model="selectedLayerId"
        @update:modelValue="chooseLayer"
        class="profile-shards-tabs world-layer-tabs"
        color="primary"
        show-arrows
      >
        <v-tab v-for="layer in layers" :key="layer.id" :value="String(layer.id)">
          {{ formatLayerLabel(layer) }} · {{ layer.occupancy }}/{{ layer.capacity }}
        </v-tab>
      </v-tabs>

      <p v-else class="muted">Слои еще не созданы.</p>
    </section>

    <section class="world-layout">
      <section class="card world-canvas-card card--dark">
        <div class="world-canvas-card__header">
          <div>
            <h2>Сцена</h2>
            <p class="muted">Заглушки вместо ассетов, но уже с живой картой, мобами, ресурсами и боссом.</p>
            <p class="muted world-canvas-card__summary">{{ sceneSummary }}</p>
          </div>
          <button class="ghost" type="button" :disabled="refreshing" @click="refreshWorld">
            {{ refreshing ? "Обновляем..." : "Обновить" }}
          </button>
        </div>

        <div v-if="loading" class="world-loading">
          <v-skeleton-loader type="image, article" />
        </div>

        <div v-else class="world-canvas-shell">
          <div ref="pixiHostRef" class="world-canvas"></div>
          <div class="world-legend">
            <span><i class="legend-dot legend-dot--player"></i> Игроки и боты</span>
            <span><i class="legend-dot legend-dot--mob"></i> Мобы</span>
            <span><i class="legend-dot legend-dot--resource"></i> Ресурсы</span>
            <span><i class="legend-dot legend-dot--boss"></i> Босс</span>
          </div>
        </div>
      </section>

      <aside class="world-sidebar">
        <section class="card card--dark world-panel">
          <h2>Прогресс</h2>
          <div v-if="world" class="detail-list">
            <div><span>Слой</span><strong>{{ world.progress.layer_index }}</strong></div>
            <div><span>Участники</span><strong>{{ world.progress.occupancy }}/{{ world.progress.capacity }}</strong></div>
            <div><span>Энергия</span><strong>{{ world.progress.energy_flow }}</strong></div>
            <div><span>Время</span><strong>{{ world.progress.elapsed_hours }} / {{ world.progress.required_hours }} ч</strong></div>
            <div><span>Цикл босса</span><strong>{{ world.progress.boss_unlock_progress }}%</strong></div>
            <div><span>XP банк</span><strong>{{ world.inventory.banked_xp }}</strong></div>
          </div>
          <v-progress-linear
            v-if="world"
            class="world-progress"
            :model-value="world.progress.boss_unlock_progress"
            color="primary"
            height="12"
          />
          <p class="muted world-panel__hint">XP на аккаунт зачисляется после убийства босса, до этого идет только в банк.</p>
        </section>

        <section class="card card--dark world-panel">
          <h2>Состав слоя</h2>
          <div v-if="activeLayer && activeLayer.members.length" class="world-member-list">
            <div v-for="member in activeLayer.members" :key="member.id" class="world-member">
              <strong>{{ member.nickname }}</strong>
              <span>{{ member.owner ? "Владелец" : "Участник" }}</span>
            </div>
          </div>
          <p v-else class="muted">Пока никто не вошел в этот слой.</p>
        </section>

        <section class="card card--dark world-panel">
          <h2>Босс</h2>
          <div v-if="world" class="detail-list">
            <div><span>Имя</span><strong>{{ world.boss.name }}</strong></div>
            <div><span>HP</span><strong>{{ world.boss.hp }} / {{ world.boss.max_hp }}</strong></div>
            <div><span>Цель</span><strong>Минимум {{ world.boss.required_participants }} игрока и {{ world.boss.required_hours }} ч, 10 игроков укладывают цикл в 1 ч</strong></div>
            <div><span>Готов</span><strong>{{ world.boss.ready ? "Да" : "Нет" }}</strong></div>
          </div>
          <p v-else class="muted">Босс появится после загрузки мира.</p>
        </section>

        <section class="card card--dark world-panel">
          <h2>Инвентарь</h2>
          <div v-if="world" class="detail-list">
            <div><span>Лут</span><strong>{{ world.inventory.loot }}</strong></div>
            <div><span>Энергия</span><strong>{{ world.inventory.energy }}</strong></div>
            <div><span>Лечение</span><strong>{{ world.inventory.healing }}</strong></div>
            <div><span>Руда</span><strong>{{ world.inventory.shard_ore }}</strong></div>
            <div><span>Банк XP</span><strong>{{ world.inventory.pending_xp }}</strong></div>
          </div>
        </section>
      </aside>
    </section>

    <p v-if="error" class="news-error">{{ error }}</p>
  </main>
</template>

<style scoped>
.world-page {
  display: grid;
  gap: var(--space-m);
  min-height: calc(100vh - 7.5rem);
}

.world-hero {
  display: grid;
  gap: var(--space-s);
  border-inline-start: 4px solid var(--farmspot-primary);
}

.world-hero__meta {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs);
}

.world-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.35fr) minmax(280px, 0.65fr);
  gap: var(--space-l);
}

.world-canvas-card,
.world-panel {
  display: grid;
  gap: var(--space-s);
}

.world-canvas-card__header,
.profile-grid-card__header {
  display: flex;
  justify-content: space-between;
  gap: var(--space-s);
  align-items: flex-start;
}

.world-canvas-card__summary {
  margin-top: var(--space-2xs);
}

.world-canvas-shell {
  display: grid;
  gap: var(--space-s);
}

.world-canvas {
  width: 100%;
  aspect-ratio: 28 / 16;
  border-radius: var(--radius-l);
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: linear-gradient(180deg, rgba(10, 13, 20, 0.95), rgba(20, 25, 35, 0.95));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
}

.world-legend {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs) var(--space-s);
  color: var(--farmspot-text-on-dark-muted);
  font-size: var(--step--1);
}

.world-legend span {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2xs);
}

.legend-dot {
  width: 0.7rem;
  height: 0.7rem;
  border-radius: 999px;
  display: inline-block;
}

.legend-dot--player {
  background: #ffd18a;
}

.legend-dot--mob {
  background: #ff8858;
}

.legend-dot--resource {
  background: #9de7a5;
}

.legend-dot--boss {
  background: #bf4444;
}

.world-sidebar {
  display: grid;
  gap: var(--space-l);
  align-content: start;
}

.world-member-list {
  display: grid;
  gap: var(--space-xs);
}

.world-member {
  display: flex;
  justify-content: space-between;
  gap: var(--space-s);
  padding: var(--space-2xs) 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.world-progress {
  margin-top: var(--space-xs);
}

.world-panel__hint {
  margin: 0;
}

.world-loading {
  min-height: 20rem;
}

@media (max-width: 960px) {
  .world-layout {
    grid-template-columns: 1fr;
  }
}
</style>
