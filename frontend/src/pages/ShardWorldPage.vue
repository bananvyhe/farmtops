<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import { useRoute, RouterLink } from "vue-router"
import { api } from "../api"

const route = useRoute()
const loading = ref(true)
const refreshing = ref(false)
const error = ref("")
const worldResponse = ref(null)
const selectedLayerId = ref(null)
const canvasRef = ref(null)
let frameHandle = null
let refreshHandle = null

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

function drawWorld(timestamp) {
  const canvas = canvasRef.value
  const ctx = canvas?.getContext("2d")
  if (!canvas || !ctx || !world.value) return

  const dpr = window.devicePixelRatio || 1
  const cssWidth = canvas.clientWidth || 960
  const cssHeight = canvas.clientHeight || 560
  if (canvas.width !== Math.floor(cssWidth * dpr) || canvas.height !== Math.floor(cssHeight * dpr)) {
    canvas.width = Math.floor(cssWidth * dpr)
    canvas.height = Math.floor(cssHeight * dpr)
  }

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, cssWidth, cssHeight)

  const grid = world.value.map
  const gridWidth = Number(grid.width || 28)
  const gridHeight = Number(grid.height || 16)
  const tiles = Array.isArray(grid.tiles) ? grid.tiles : []
  const tileSize = Math.max(12, Math.floor(Math.min(cssWidth / gridWidth, (cssHeight - 24) / gridHeight)))
  const mapWidth = gridWidth * tileSize
  const mapHeight = gridHeight * tileSize
  const offsetX = Math.floor((cssWidth - mapWidth) / 2)
  const offsetY = Math.floor((cssHeight - mapHeight) / 2)
  const pulse = Math.sin(timestamp / 500)

  const bg = ctx.createLinearGradient(0, 0, cssWidth, cssHeight)
  bg.addColorStop(0, "#0a0d14")
  bg.addColorStop(1, "#141923")
  ctx.fillStyle = bg
  ctx.fillRect(0, 0, cssWidth, cssHeight)

  tiles.forEach((row, y) => {
    row.forEach((tile, x) => {
      const px = offsetX + x * tileSize
      const py = offsetY + y * tileSize

      switch (tile) {
        case "water":
          ctx.fillStyle = "#123d5c"
          break
        case "stone":
          ctx.fillStyle = "#525965"
          break
        case "dirt":
          ctx.fillStyle = "#6d4b2f"
          break
        case "boss":
          ctx.fillStyle = "#6d1f1f"
          break
        default:
          ctx.fillStyle = "#20331f"
          break
      }

      ctx.fillRect(px, py, tileSize, tileSize)
      ctx.strokeStyle = "rgba(255,255,255,0.03)"
      ctx.strokeRect(px, py, tileSize, tileSize)
    })
  })

  const drawOrb = (entity, fill, radius, alpha = 1) => {
    const wobble = Math.sin(timestamp / 300 + entity.x + entity.y)
    const cx = offsetX + entity.x * tileSize + tileSize / 2
    const cy = offsetY + entity.y * tileSize + tileSize / 2
    ctx.globalAlpha = alpha
    ctx.beginPath()
    ctx.fillStyle = fill
    ctx.arc(cx, cy + wobble * 2, radius, 0, Math.PI * 2)
    ctx.fill()
    ctx.globalAlpha = 1
  }

  world.value.resources.forEach((resource) => {
    const radius = resource.kind === "shard_ore" ? 7 : 5
    const fill = resource.kind === "energy_crystal" ? "#83d8ff" : resource.kind === "heal_herb" ? "#96ef9a" : "#d9b065"
    drawOrb(resource, fill, radius, 0.96)
  })

  world.value.mobs.forEach((mob, index) => {
    const jitterX = Math.sin(timestamp / 1000 + index) * 0.6
    const jitterY = Math.cos(timestamp / 900 + index) * 0.6
    const entity = { ...mob, x: mob.x + jitterX, y: mob.y + jitterY }
    drawOrb(entity, "#ff8858", 7 + (mob.level % 2), 0.88)
  })

  world.value.players.forEach((player, index) => {
    const jitter = Math.sin(timestamp / 700 + index) * 0.45
    const entity = {
      ...player,
      x: clamp(player.x + jitter, 0, gridWidth - 1),
      y: clamp(player.y + jitter, 0, gridHeight - 1)
    }
    drawOrb(entity, index === 0 ? "#ffd18a" : "#7dd3fc", 9, 1)
  })

  const boss = world.value.boss
  const bossCx = offsetX + boss.x * tileSize + tileSize / 2
  const bossCy = offsetY + boss.y * tileSize + tileSize / 2 + Math.sin(timestamp / 400) * 3
  ctx.beginPath()
  ctx.fillStyle = "#b93b3b"
  ctx.arc(bossCx, bossCy, 14 + Math.sin(pulse) * 2, 0, Math.PI * 2)
  ctx.fill()
  ctx.strokeStyle = "rgba(255, 210, 210, 0.45)"
  ctx.lineWidth = 2
  ctx.stroke()
}

function animationLoop(timestamp) {
  drawWorld(timestamp)
  frameHandle = window.requestAnimationFrame(animationLoop)
}

onMounted(async () => {
  await loadWorld()
  await enterLayer(selectedLayerId.value)
  frameHandle = window.requestAnimationFrame(animationLoop)
  refreshHandle = window.setInterval(refreshWorld, 4000)
})

onBeforeUnmount(() => {
  if (frameHandle) window.cancelAnimationFrame(frameHandle)
  if (refreshHandle) window.clearInterval(refreshHandle)
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
          </div>
          <button class="ghost" type="button" :disabled="refreshing" @click="refreshWorld">
            {{ refreshing ? "Обновляем..." : "Обновить" }}
          </button>
        </div>

        <div v-if="loading" class="world-loading">
          <v-skeleton-loader type="image, article" />
        </div>

        <div v-else class="world-canvas-shell">
          <canvas ref="canvasRef" class="world-canvas" />
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
            <div><span>Групповой прогресс</span><strong>{{ world.progress.group_progress }}%</strong></div>
          </div>
          <v-progress-linear
            v-if="world"
            class="world-progress"
            :model-value="world.progress.group_progress"
            color="primary"
            height="12"
          />
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
            <div><span>Цель</span><strong>Удержать прогресс группы и подготовить шард к дальнейшему фарму</strong></div>
          </div>
          <p v-else class="muted">Босс появится после загрузки мира.</p>
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

.world-loading {
  min-height: 20rem;
}

@media (max-width: 960px) {
  .world-layout {
    grid-template-columns: 1fr;
  }
}
</style>
