<script setup>
import { Application, Container, Graphics, Text } from "pixi.js"
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue"
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
let pixiMounted = false

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

function easeInOutCubic(value) {
  if (value < 0.5) return 4 * value * value * value
  const offset = -2 * value + 2
  return 1 - (offset * offset * offset) / 2
}

function phaseDistance(from, to) {
  const forward = ((to - from) % 1 + 1) % 1
  return Math.min(forward, 1 - forward)
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

  const routeSpeedFactor = Number(player.route_speed_factor || 1)
  const phase = (routeProgressFromTimestamp(player, timestamp) * routeSpeedFactor) % 1
  const resourceStopPhase = Number(player.resource_stop_phase || 0.24)
  const resourceStopWindow = Number(player.resource_stop_window || 0.08)
  const stopDistance = phaseDistance(phase, resourceStopPhase)
  const resourceX = Number(player.resource_target_x ?? player.x ?? 0)
  const resourceY = Number(player.resource_target_y ?? player.y ?? 0)

  if (stopDistance < resourceStopWindow / 2) {
    const orbitPhase = timestamp / 1200 + Number(player.route_offset_seconds || 0) / 7
    const orbitRadius = 0.18 + Number(player.route_cycle_seconds || 48) / 1200
    return {
      x: resourceX + Math.cos(orbitPhase) * orbitRadius,
      y: resourceY + Math.sin(orbitPhase * 1.2) * orbitRadius * 0.7,
      phase,
      action: "gather"
    }
  }

  const segmentCount = path.length - 1
  const segmentFloat = phase * segmentCount
  const segmentIndex = Math.min(segmentCount - 1, Math.floor(segmentFloat))
  const localPhase = easeInOutCubic(segmentFloat - segmentIndex)
  const from = path[segmentIndex]
  const to = path[segmentIndex + 1]
  const dx = Number(to.x || 0) - Number(from.x || 0)
  const dy = Number(to.y || 0) - Number(from.y || 0)
  const length = Math.max(Math.hypot(dx, dy), 0.0001)
  const swayPhase = Math.sin(timestamp / 2400 + Number(player.route_offset_seconds || 0) / 3)
  const sway = 0.1 + Number(player.route_cycle_seconds || 48) / 1400
  const swayX = (-dy / length) * sway * swayPhase
  const swayY = (dx / length) * sway * swayPhase
  const action = player.action || (segmentIndex === 0 ? "gather" : segmentIndex === 1 ? "fight" : "return")

  return {
    x: lerp(Number(from.x || 0), Number(to.x || 0), localPhase) + swayX,
    y: lerp(Number(from.y || 0), Number(to.y || 0), localPhase) + swayY,
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

async function mountPixiScene() {
  if (pixiMounted || !pixiHostRef.value) return

  app = new Application()
  const hostWidth = pixiHostRef.value.clientWidth || 960
  const hostHeight = pixiHostRef.value.clientHeight || 560
  await app.init({
    background: "#0a0d14",
    width: hostWidth,
    height: hostHeight,
    antialias: false,
    autoDensity: true,
    resolution: window.devicePixelRatio || 1
  })

  stageContainer = new Container()
  stageContainer.sortableChildren = true
  app.stage.addChild(stageContainer)
  app.canvas.style.width = "100%"
  app.canvas.style.height = "100%"
  pixiHostRef.value.appendChild(app.canvas)
  pixiMounted = true
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
  if (!app || !stageContainer) return

  const metrics = getWorldMetrics()
  const { gridWidth, gridHeight, tiles, width, height, tileSize, offsetX, offsetY, mapWidth, mapHeight } = metrics
  const hasWorld = Boolean(world.value)
  const progress = Number(world.value?.progress?.boss_unlock_progress || world.value?.progress?.group_progress || 0)
  const stage = stageContainer

  stage.removeChildren()

  const background = new Graphics()
  background.rect(0, 0, width, height).fill(hexColor("#0a0d14"))
  stage.addChild(background)

  const aura = new Graphics()
  aura.circle(width / 2, height / 2, Math.min(width, height) * 0.38).fill({ color: hexColor("#121826"), alpha: 0.8 })
  stage.addChild(aura)

  const gridGfx = new Graphics()
  if (!hasWorld) {
    const panel = new Graphics()
    panel.roundRect(offsetX, offsetY, mapWidth, mapHeight, 20).fill({ color: hexColor("#111722"), alpha: 0.88 })
    panel.roundRect(offsetX, offsetY, mapWidth, mapHeight, 20).stroke({ width: 1, color: hexColor("#ffffff"), alpha: 0.08 })
    const placeholder = new Graphics()
    placeholder.circle(width / 2, height / 2, Math.min(width, height) * 0.12).stroke({ width: 3, color: hexColor("#c75923"), alpha: 0.7 })
    placeholder.circle(width / 2, height / 2, Math.min(width, height) * 0.075).fill({ color: hexColor("#c75923"), alpha: 0.18 })
    stage.addChild(panel)
    stage.addChild(placeholder)
    stage.addChild(gridGfx)

    const loadingHint = new Graphics()
    loadingHint.roundRect(width / 2 - 120, height / 2 + 38, 240, 26, 13).fill({ color: hexColor("#1c2433"), alpha: 0.92 })
    loadingHint.roundRect(width / 2 - 120, height / 2 + 38, 120, 26, 13).fill({ color: hexColor("#7dd3fc"), alpha: 0.72 })
    stage.addChild(loadingHint)
    return
  }

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
  const routeNodesGfx = new Graphics()
  world.value.players.forEach((player) => {
    if (!Array.isArray(player.path) || player.path.length < 2) return
    const points = player.path.map((point) => ({
      x: offsetX + point.x * tileSize + tileSize / 2,
      y: offsetY + point.y * tileSize + tileSize / 2
    }))
    routeGfx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((point) => routeGfx.lineTo(point.x, point.y))
    routeGfx.stroke({ width: 1, color: hexColor("#7dd3fc"), alpha: 0.08 })
    points.forEach((point, pointIndex) => {
      const radius = pointIndex === 0 || pointIndex === points.length - 1 ? 2.5 : 1.8
      routeNodesGfx.circle(point.x, point.y, radius).fill({ color: hexColor("#7dd3fc"), alpha: 0.12 })
    })
  })
  stage.addChild(routeGfx)
  stage.addChild(routeNodesGfx)

  const entities = new Container()
  const shapes = new Graphics()
  const labels = new Container()
  entities.addChild(shapes)
  entities.addChild(labels)

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
    const pulsePhase = Number(resource.pulse_phase || 0) + timestamp / (900 / Number(resource.pulse_speed || 1))
    const pulse = 0.5 + Math.sin(pulsePhase) * 0.5
    shapes.circle(cx, cy, radius + 4 + pulse * 2).fill({ color: hexColor(fill), alpha: 0.08 + pulse * 0.06 })
    shapes.circle(cx, cy, radius + pulse * 0.8).stroke({ width: 1.2, color: hexColor(fill), alpha: 0.24 + pulse * 0.2 })
    shapes.circle(cx, cy, radius).fill({ color: hexColor(fill), alpha: 0.92 })
  })

  world.value.drops?.forEach((drop) => {
    const cx = offsetX + drop.x * tileSize + tileSize / 2
    const cy = offsetY + drop.y * tileSize + tileSize / 2
    const fill = drop.rarity === "rare" ? "#f7c86b" : "#c8d0da"
    shapes.roundRect(cx - 4, cy - 4, 8, 8, 2).fill({ color: hexColor(fill), alpha: 0.8 })
  })

  world.value.mobs.forEach((mob, index) => {
    if (mob.alive === false) return
    const anchorX = Number(mob.anchor_x ?? mob.x ?? 0)
    const anchorY = Number(mob.anchor_y ?? mob.y ?? 0)
    const patrolRadius = Number(mob.patrol_radius || 0.9)
    const patrolSpeed = Number(mob.patrol_speed || 0.12)
    const patrolPhase = Number(mob.patrol_phase || 0)
    const driftX = Math.sin(timestamp / (1100 / patrolSpeed) + patrolPhase + index * 0.4) * patrolRadius
    const driftY = Math.cos(timestamp / (1300 / patrolSpeed) + patrolPhase + index * 0.3) * (patrolRadius * 0.7)
    const cx = offsetX + (anchorX + driftX) * tileSize + tileSize / 2
    const cy = offsetY + (anchorY + driftY) * tileSize + tileSize / 2
    shapes.circle(cx, cy, 7 + (mob.level % 2)).fill({ color: hexColor("#ff8858"), alpha: 0.82 })
    shapes.circle(cx, cy, 11).stroke({ width: 1, color: hexColor("#ff8858"), alpha: 0.1 })
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
    shapes.circle(cx, cy, 10).fill({ color: hexColor(color), alpha: 1 })
    shapes.circle(cx, cy, 14).stroke({ width: 1, color: hexColor(color), alpha: 0.24 })
    shapes.circle(cx + 11, cy + 11, 2.2).fill({ color: hexColor(color), alpha: 0.72 })

    const label = new Text({
      text: player.nickname,
      style: {
        fontFamily: "Arial",
        fontSize: 12,
        fill: 0xf3f5f8,
        stroke: { color: 0x0a0d14, width: 4 },
        align: "center"
      }
    })
    label.anchor.set(0.5, 1)
    label.x = cx
    label.y = cy - 13
    label.alpha = 0.92
    labels.addChild(label)
  })

  const boss = world.value.boss
  const bossCx = offsetX + boss.x * tileSize + tileSize / 2
  const bossCy = offsetY + boss.y * tileSize + tileSize / 2 + Math.sin(timestamp / 400) * 2
  shapes.circle(bossCx, bossCy, 16 + Math.sin(timestamp / 500) * 2).fill({ color: hexColor("#b93b3b"), alpha: 1 })
  shapes.circle(bossCx, bossCy, 22).stroke({ width: 2, color: hexColor("#ffd2d2"), alpha: 0.45 })
  stage.addChild(entities)

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
  await nextTick()
  await mountPixiScene()
  frameHandle = window.requestAnimationFrame(animationLoop)
  await loadWorld()
  await enterLayer(selectedLayerId.value)
  refreshHandle = window.setInterval(refreshWorld, 4000)
})

onBeforeUnmount(() => {
  if (frameHandle) window.cancelAnimationFrame(frameHandle)
  if (refreshHandle) window.clearInterval(refreshHandle)
  app?.destroy(true, { children: true, texture: true, context: true })
  app = null
  stageContainer = null
  pixiMounted = false
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
        <span class="profile-pill">Режим: {{ world?.mode || "—" }}</span>
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
          {{ formatLayerLabel(layer) }} · {{ layer.active_occupancy ?? layer.occupancy }}/{{ layer.capacity }}
        </v-tab>
      </v-tabs>

      <p v-else class="muted">Слои еще не созданы.</p>
    </section>

    <section class="card world-canvas-card card--dark">
      <div class="world-canvas-card__header">
        <div>
          <h2>Сцена</h2>
          <p class="muted">Заглушки вместо ассетов, но уже с живой картой, мобами, ресурсами и боссом.</p>
        </div>
        <button class="ghost" type="button" :disabled="refreshing" @click="refreshWorld">
          {{ refreshing ? "Обновляем..." : "Обновить" }}
        </button>
      </div>

      <div class="world-scene-hud world-scene-hud--top" v-if="world">
        <div class="world-scene-stat">
          <span>Цикл босса</span>
          <strong>{{ world.progress.boss_unlock_progress }}%</strong>
        </div>
        <div class="world-scene-stat">
          <span>Время</span>
          <strong>{{ world.progress.elapsed_hours }} / {{ world.progress.required_hours }} ч</strong>
        </div>
        <div class="world-scene-stat">
          <span>Участники</span>
          <strong>{{ world.progress.occupancy }}/{{ world.progress.capacity }}</strong>
        </div>
        <div class="world-scene-stat">
          <span>Активны</span>
          <strong>{{ world.active_players_count }}</strong>
        </div>
        <div class="world-scene-stat">
          <span>XP банк</span>
          <strong>{{ world.inventory.banked_xp }}</strong>
        </div>
        <div class="world-scene-stat">
          <span>UTC слот</span>
          <strong>{{ world.current_week_slot_utc }}</strong>
        </div>
      </div>

      <div class="world-canvas-shell">
        <div class="world-canvas-frame">
          <div ref="pixiHostRef" class="world-canvas"></div>
          <div class="world-fallback">
            <div class="world-fallback__grid"></div>
            <div class="world-fallback__core"></div>
            <div class="world-fallback__label">Loading shard scene</div>
          </div>
          <div v-if="loading" class="world-loading">
            <v-skeleton-loader type="image, article" />
          </div>
        </div>
      <div class="world-scene-hud world-scene-hud--bottom">
        <div class="world-legend">
          <span><i class="legend-dot legend-dot--player"></i> Игроки и боты</span>
          <span><i class="legend-dot legend-dot--mob"></i> Мобы</span>
          <span><i class="legend-dot legend-dot--resource"></i> Ресурсы</span>
          <span><i class="legend-dot legend-dot--boss"></i> Босс</span>
        </div>
        <p class="world-scene-caption">{{ sceneSummary }}</p>
      </div>
      </div>
    </section>

    <section class="world-info-grid">
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
            <span>{{ member.owner ? "Владелец" : "Участник" }} · {{ member.active_now ? "Активен" : "Вне прайма" }}</span>
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

      <section class="card card--dark world-panel world-panel--wide">
        <h2>Фарм-лог</h2>
        <div v-if="world && world.farm_log?.length" class="world-log-list">
          <div v-for="entry in world.farm_log" :key="entry.players.join('-')" class="world-log-item">
            <strong>{{ entry.players.join(" + ") }}</strong>
            <span>{{ entry.shared_prime_hours }} ч совпадения · {{ entry.together_minutes }} мин вместе</span>
          </div>
        </div>
        <p v-else class="muted">Сейчас нет совпавших праймов, поэтому фарм-лог пуст.</p>
      </section>
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
  gap: var(--space-l);
  align-items: start;
}

.world-info-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--space-l);
}

.world-canvas-card,
.world-panel {
  display: grid;
  gap: var(--space-s);
}

.world-canvas-card {
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
}

.world-canvas-card__header,
.profile-grid-card__header {
  display: flex;
  justify-content: space-between;
  gap: var(--space-s);
  align-items: flex-start;
}

.world-canvas-shell {
  display: grid;
  gap: var(--space-s);
  max-width: 100%;
}

.world-canvas-frame {
  position: relative;
  width: 100%;
  min-width: 0;
}

.world-canvas {
  position: relative;
  z-index: 2;
  width: 100%;
  aspect-ratio: 36 / 20;
  min-height: 20rem;
  max-width: 100%;
  border-radius: var(--radius-l);
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: linear-gradient(180deg, rgba(10, 13, 20, 0.95), rgba(20, 25, 35, 0.95));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
}

.world-fallback {
  position: absolute;
  inset: 0;
  z-index: 1;
  border-radius: var(--radius-l);
  overflow: hidden;
  background:
    radial-gradient(circle at center, rgba(199, 89, 35, 0.16), transparent 24%),
    linear-gradient(180deg, rgba(12, 16, 24, 0.72), rgba(7, 10, 16, 0.92));
  border: 1px solid rgba(255, 255, 255, 0.04);
  pointer-events: none;
}

.world-fallback__grid {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgba(255, 255, 255, 0.04) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255, 255, 255, 0.04) 1px, transparent 1px);
  background-size: 56px 56px;
  opacity: 0.25;
}

.world-fallback__core {
  position: absolute;
  inset: 30% 34%;
  border-radius: 999px;
  border: 2px solid rgba(125, 211, 252, 0.45);
  background: radial-gradient(circle, rgba(199, 89, 35, 0.2), rgba(199, 89, 35, 0.04) 60%, transparent 70%);
  box-shadow: 0 0 0 24px rgba(125, 211, 252, 0.04);
}

.world-fallback__label {
  position: absolute;
  left: 50%;
  bottom: 18px;
  transform: translateX(-50%);
  padding: 0.45rem 0.9rem;
  border-radius: 999px;
  background: rgba(10, 13, 20, 0.82);
  color: var(--farmspot-text-on-dark);
  font-size: var(--step--1);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.world-loading {
  position: absolute;
  inset: 0;
  z-index: 3;
  display: grid;
  align-content: center;
  padding: var(--space-m);
  background: rgba(10, 13, 20, 0.72);
  border-radius: var(--radius-l);
  pointer-events: none;
}

.world-scene-hud {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs);
  align-items: center;
  justify-content: space-between;
  max-width: 100%;
}

.world-scene-hud--top {
  padding: var(--space-2xs) var(--space-xs);
  border-radius: var(--radius-l);
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.06);
}

.world-scene-hud--bottom {
  padding-top: var(--space-2xs);
}

.world-scene-stat {
  display: grid;
  gap: var(--space-3xs);
  min-width: 120px;
}

.world-scene-stat span {
  color: var(--farmspot-text-on-dark-muted);
  font-size: var(--step--2);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.world-scene-stat strong {
  color: var(--farmspot-text-on-dark);
  font-size: var(--step-0);
}

.world-scene-caption {
  color: var(--farmspot-text-on-dark-muted);
  font-size: var(--step--1);
  margin: 0;
}

.world-legend {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs) var(--space-s);
  color: var(--farmspot-text-on-dark-muted);
  font-size: var(--step--1);
}

.world-scene-hud--top .world-scene-stat strong {
  color: var(--farmspot-text-on-dark);
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

.world-panel--wide {
  grid-column: 1 / -1;
}

.world-log-list {
  display: grid;
  gap: var(--space-xs);
}

.world-log-item {
  display: flex;
  justify-content: space-between;
  gap: var(--space-s);
  padding: var(--space-2xs) 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.world-log-item strong {
  color: var(--farmspot-text-on-dark);
}

.world-log-item span {
  color: var(--farmspot-text-on-dark-muted);
}

@media (max-width: 960px) {
  .world-layout {
    grid-template-columns: 1fr;
  }

  .world-info-grid {
    grid-template-columns: 1fr;
  }
}
</style>
