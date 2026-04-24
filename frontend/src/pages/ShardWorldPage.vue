<script setup>
import { Application, Container, Graphics, Text } from "pixi.js"
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue"
import { useRoute } from "vue-router"
import { api, currentCsrfToken } from "../api"

const route = useRoute()
const loading = ref(true)
const refreshing = ref(false)
const error = ref("")
const worldResponse = ref(null)
const selectedLayerId = ref(null)
const chatMessages = ref([])
const chatDraft = ref("")
const chatSending = ref(false)
const pixiHostRef = ref(null)
const chatMessagesRef = ref(null)
const sceneSummary = ref("")
let frameHandle = null
let renderHandle = null
let refreshHandle = null
let visibilityHandler = null
let cableSocket = null
let cableReconnectHandle = null
let cableIdentifier = null
let componentUnmounted = false
let pageHideHandler = null
let app = null
let stageContainer = null
let pixiMounted = false
const renderState = {
  seed: null,
  players: new Map(),
  mobs: new Map(),
  boss: null
}

const shard = computed(() => worldResponse.value?.shard || null)
const layers = computed(() => worldResponse.value?.layers || [])
const world = computed(() => worldResponse.value?.world || null)
const activeLayer = computed(() => layers.value.find((layer) => String(layer.id) === String(selectedLayerId.value)) || null)
const canSendChat = computed(() => Boolean(chatDraft.value.trim()) && !chatSending.value)

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

function currentSceneInventory() {
  return world.value?.inventory || {}
}

function farmLogPlayers(entry) {
  if (Array.isArray(entry?.players) && entry.players.length) return entry.players
  if (entry?.player) return [entry.player]
  return ["—"]
}

function farmLogDuration(entry) {
  if (entry?.together_minutes != null) return `${entry.together_minutes} мин вместе`
  if (entry?.shared_prime_hours != null) return `${entry.shared_prime_hours} ч совпадения`
  return "ожидает агрегации"
}

function resetRenderState(seed = null) {
  renderState.seed = seed
  renderState.players.clear()
  renderState.mobs.clear()
  renderState.boss = null
}

function scrollChatToBottom() {
  if (!chatMessagesRef.value) return
  chatMessagesRef.value.scrollTop = chatMessagesRef.value.scrollHeight
}

function setChatMessages(messages) {
  chatMessages.value = Array.isArray(messages) ? messages.slice(-100) : []
  nextTick(scrollChatToBottom)
}

function appendChatMessage(message) {
  if (!message?.id) return
  const messageId = Number(message.id)
  if (chatMessages.value.some((item) => Number(item.id) === messageId)) return
  chatMessages.value = [...chatMessages.value, message].slice(-100)
  nextTick(scrollChatToBottom)
}

function mergeWorldResponse(payload) {
  if (!payload) return
  worldResponse.value = payload
  if (!selectedLayerId.value || !layers.value.some((layer) => String(layer.id) === String(selectedLayerId.value))) {
    selectedLayerId.value = payload.active_layer_id || payload.layers?.[0]?.id || null
  }
  if (Array.isArray(payload.chat_messages)) {
    setChatMessages(payload.chat_messages)
  }
}

function smoothPosition(current, target, factor = 0.12) {
  return current + (target - current) * factor
}

function syncRenderState(snapshot) {
  if (!snapshot?.seed) {
    resetRenderState()
    return
  }

  if (renderState.seed !== snapshot.seed) {
    resetRenderState(snapshot.seed)
  }

  const playerIds = new Set()
  snapshot.players.forEach((player) => {
    const target = {
      x: Number(player.x || 0),
      y: Number(player.y || 0)
    }
    playerIds.add(String(player.id))

    if (!renderState.players.has(String(player.id))) {
      renderState.players.set(String(player.id), { ...target })
      return
    }

    const current = renderState.players.get(String(player.id))
      current.x = smoothPosition(current.x, target.x, 0.05)
      current.y = smoothPosition(current.y, target.y, 0.05)
  })

  Array.from(renderState.players.keys()).forEach((id) => {
    if (!playerIds.has(id)) renderState.players.delete(id)
  })

  const mobIds = new Set()
  snapshot.mobs.forEach((mob) => {
    const target = {
      x: Number(mob.x || 0),
      y: Number(mob.y || 0)
    }
    mobIds.add(String(mob.id))

    if (!renderState.mobs.has(String(mob.id))) {
      renderState.mobs.set(String(mob.id), { ...target })
      return
    }

    const current = renderState.mobs.get(String(mob.id))
    current.x = smoothPosition(current.x, target.x, 0.04)
    current.y = smoothPosition(current.y, target.y, 0.04)
  })

  Array.from(renderState.mobs.keys()).forEach((id) => {
    if (!mobIds.has(id)) renderState.mobs.delete(id)
  })

  renderState.boss = {
    x: Number(snapshot.boss?.x || 0),
    y: Number(snapshot.boss?.y || 0)
  }
}

async function enterLayer(layerId = null) {
  const shardId = route.params.id
  refreshing.value = true
  error.value = ""

  try {
    const data = await api.enterShard(shardId, layerId)
    mergeWorldResponse(data)
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
    mergeWorldResponse(data)
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}

async function refreshWorld() {
  if (!route.params.id) return
  if (refreshing.value || loading.value || document.hidden) return

  refreshing.value = true
  try {
    const data = await api.shardWorld(route.params.id)
    mergeWorldResponse(data)
  } catch (err) {
    error.value = err.message
  } finally {
    refreshing.value = false
  }
}

function cableUrl() {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws"
  return `${protocol}://${window.location.host}/cable`
}

function cableConnected() {
  return cableSocket && cableSocket.readyState === WebSocket.OPEN
}

function sendCableCommand(action, payload = {}) {
  if (!cableConnected() || !cableIdentifier) return false

  cableSocket.send(
    JSON.stringify({
      command: "message",
      identifier: cableIdentifier,
      data: JSON.stringify({ action, ...payload })
    })
  )
  return true
}

function connectShardCable() {
  if (!route.params.id) return

  if (cableReconnectHandle) {
    window.clearTimeout(cableReconnectHandle)
    cableReconnectHandle = null
  }
  if (cableSocket) {
    cableSocket.close()
    cableSocket = null
  }

  cableIdentifier = JSON.stringify({ channel: "ShardChannel", shard_id: String(route.params.id) })
  cableSocket = new WebSocket(cableUrl())

  cableSocket.addEventListener("open", () => {
    cableSocket.send(
      JSON.stringify({
        command: "subscribe",
        identifier: cableIdentifier
      })
    )
  })

  cableSocket.addEventListener("message", (event) => {
    let packet = {}
    try {
      packet = JSON.parse(event.data || "{}")
    } catch (_) {
      return
    }
    if (packet.type === "ping" || packet.type === "welcome" || packet.type === "confirm_subscription") return
    if (!packet.message) return

    const message = packet.message
    if (message.type === "world_snapshot" && message.payload) {
      mergeWorldResponse(message.payload)
      return
    }
    if (message.type === "chat_bootstrap" && Array.isArray(message.messages)) {
      setChatMessages(message.messages)
      return
    }
    if (message.type === "chat_message" && message.message) {
      appendChatMessage(message.message)
    }
  })

  cableSocket.addEventListener("close", () => {
    if (componentUnmounted) return
    cableReconnectHandle = window.setTimeout(connectShardCable, 2000)
  })
}

function leaveShardKeepalive() {
  const shardId = route.params.id
  if (!shardId) return

  const headers = { Accept: "application/json" }
  const csrfToken = currentCsrfToken()
  if (csrfToken) headers["X-CSRF-Token"] = csrfToken

  fetch(`/api/shards/${shardId}/leave`, {
    method: "DELETE",
    headers,
    keepalive: true,
    credentials: "same-origin"
  }).catch(() => {})
}

async function sendChatMessage() {
  const content = chatDraft.value.trim()
  if (!content || chatSending.value) return

  chatSending.value = true
  error.value = ""

  try {
    const sentViaCable = sendCableCommand("speak", { content })
    if (!sentViaCable) {
      const data = await api.createShardChatMessage(route.params.id, { content })
      appendChatMessage(data.message)
    }
    chatDraft.value = ""
  } catch (err) {
    error.value = err.message
  } finally {
    chatSending.value = false
  }
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
    preference: "canvas",
    antialias: false,
    autoStart: false,
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
  const inventory = world.value?.inventory || {}
  const stage = stageContainer

  syncRenderState(world.value)

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

  const entities = new Container()
  const shapes = new Graphics()
  const labels = new Container()
  entities.addChild(shapes)
  entities.addChild(labels)

  world.value.resources.forEach((resource) => {
    if (resource.alive === false) return
    const isEnergy = resource.kind === "energy_crystal"
    const radius = isEnergy ? 6 : 9
    const fill = isEnergy ? "#83d8ff" : "#d9b065"
    const cx = offsetX + resource.x * tileSize + tileSize / 2
    const cy = offsetY + resource.y * tileSize + tileSize / 2
    const pulsePhase = Number(resource.pulse_phase || 0) + timestamp / (900 / Number(resource.pulse_speed || 1))
    const pulse = 0.5 + Math.sin(pulsePhase) * 0.5
    if (isEnergy) {
      shapes.circle(cx, cy, radius + 4 + pulse * 2).fill({ color: hexColor(fill), alpha: 0.08 + pulse * 0.06 })
      shapes.circle(cx, cy, radius + pulse * 0.8).stroke({ width: 1.2, color: hexColor(fill), alpha: 0.24 + pulse * 0.2 })
      shapes.circle(cx, cy, radius).fill({ color: hexColor(fill), alpha: 0.94 })
      shapes.circle(cx, cy, radius * 0.38).fill({ color: hexColor("#f5fdff"), alpha: 0.95 })
    } else {
      shapes.roundRect(cx - radius, cy - radius, radius * 2, radius * 2, 3).fill({ color: hexColor(fill), alpha: 0.9 })
      shapes.roundRect(cx - radius - 2, cy - radius - 2, radius * 2 + 4, radius * 2 + 4, 4).stroke({ width: 1.2, color: hexColor("#fff0c9"), alpha: 0.18 + pulse * 0.12 })
      shapes.rect(cx - 2, cy - radius + 2, 4, radius * 2 - 4).fill({ color: hexColor("#6d4b2f"), alpha: 0.35 })
    }
  })

  world.value.drops?.forEach((drop) => {
    const cx = offsetX + drop.x * tileSize + tileSize / 2
    const cy = offsetY + drop.y * tileSize + tileSize / 2
    const fill = drop.rarity === "rare" ? "#f7c86b" : "#c8d0da"
    shapes.roundRect(cx - 4, cy - 4, 8, 8, 2).fill({ color: hexColor(fill), alpha: 0.8 })
  })

  Array.from(renderState.mobs.entries()).forEach(([mobId, mobState], index) => {
    const mob = world.value.mobs.find((item) => String(item.id) === mobId) || { level: 1, alive: true }
    if (mob.alive === false) return
    const cx = offsetX + Number(mobState.x || 0) * tileSize + tileSize / 2
    const cy = offsetY + Number(mobState.y || 0) * tileSize + tileSize / 2
    const mobLevel = Number(mob.level || 1)
    shapes.circle(cx, cy, 7 + (mobLevel % 2)).fill({ color: hexColor("#ff8858"), alpha: 0.82 })
    shapes.circle(cx, cy, 11).stroke({ width: 1, color: hexColor("#ff8858"), alpha: 0.1 })
  })

  Array.from(renderState.players.entries()).forEach(([playerId, playerState], index) => {
    const player = world.value.players.find((item) => String(item.id) === playerId) || {}
    const cx = offsetX + Number(playerState.x || 0) * tileSize + tileSize / 2
    const cy = offsetY + Number(playerState.y || 0) * tileSize + tileSize / 2
    const targetX = Number(player.target_x)
    const targetY = Number(player.target_y)
    const hasTarget = Number.isFinite(targetX) && Number.isFinite(targetY)
    const color =
      player.action === "fight"
        ? "#7dd3fc"
        : player.action === "return"
          ? "#c7d2fe"
          : "#ffd18a"

    if (hasTarget) {
      const tx = offsetX + targetX * tileSize + tileSize / 2
      const ty = offsetY + targetY * tileSize + tileSize / 2
      shapes.moveTo(cx, cy)
      shapes.lineTo(tx, ty)
      shapes.stroke({ width: 1, color: hexColor(color), alpha: 0.12 })
      shapes.circle(tx, ty, 2.5).fill({ color: hexColor(color), alpha: 0.22 })
    }

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
  const bossPosition = renderState.boss || { x: boss.x, y: boss.y }
  const bossCx = offsetX + bossPosition.x * tileSize + tileSize / 2
  const bossCy = offsetY + bossPosition.y * tileSize + tileSize / 2 + Math.sin(timestamp / 400) * 2
  shapes.circle(bossCx, bossCy, 16 + Math.sin(timestamp / 500) * 2).fill({ color: hexColor("#b93b3b"), alpha: 1 })
  shapes.circle(bossCx, bossCy, 22).stroke({ width: 2, color: hexColor("#ffd2d2"), alpha: 0.45 })
  stage.addChild(entities)

  sceneSummary.value = `boss:${progress}% loot:${inventory.loot} energy:${inventory.energy} ore:${inventory.shard_ore}`
}

function animationLoop(timestamp) {
  drawWorld(timestamp)
  app?.render()
}

onMounted(async () => {
  await nextTick()
  await mountPixiScene()
  await loadWorld()
  await enterLayer()
  connectShardCable()
  drawWorld(performance.now())
  app?.render()
  renderHandle = window.setInterval(() => {
    animationLoop(performance.now())
  }, 80)
  refreshHandle = window.setInterval(() => {
    if (!sendCableCommand("tick")) refreshWorld()
  }, 3000)
  visibilityHandler = () => {
    if (document.hidden) return
    if (!sendCableCommand("tick")) refreshWorld()
  }
  pageHideHandler = () => {
    leaveShardKeepalive()
  }
  document.addEventListener("visibilitychange", visibilityHandler)
  window.addEventListener("pagehide", pageHideHandler)
})

onBeforeUnmount(() => {
  componentUnmounted = true
  leaveShardKeepalive()
  if (frameHandle) window.cancelAnimationFrame(frameHandle)
  if (renderHandle) window.clearInterval(renderHandle)
  if (refreshHandle) window.clearInterval(refreshHandle)
  if (cableReconnectHandle) window.clearTimeout(cableReconnectHandle)
  if (cableSocket) cableSocket.close()
  if (visibilityHandler) document.removeEventListener("visibilitychange", visibilityHandler)
  if (pageHideHandler) window.removeEventListener("pagehide", pageHideHandler)
  app?.destroy(true, { children: true, texture: true, context: true })
  app = null
  stageContainer = null
  pixiMounted = false
  resetRenderState()
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
        <span class="profile-pill">Общий слой: {{ activeLayer ? formatLayerLabel(activeLayer) : "—" }}</span>
        <span class="profile-pill">Режим: {{ world?.mode || "—" }}</span>
      </div>
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
          <strong>{{ currentSceneInventory().banked_xp }}</strong>
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
          <span><i class="legend-dot legend-dot--player"></i> Аватары аккаунтов</span>
          <span><i class="legend-dot legend-dot--mob"></i> Мобы</span>
          <span><i class="legend-dot legend-dot--resource legend-dot--energy"></i> Энергия</span>
          <span><i class="legend-dot legend-dot--resource legend-dot--ore"></i> Руда</span>
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
          <div><span>Лут</span><strong>{{ currentSceneInventory().loot }}</strong></div>
          <div><span>Энергия</span><strong>{{ currentSceneInventory().energy }}</strong></div>
          <div><span>Лечение</span><strong>{{ currentSceneInventory().healing }}</strong></div>
          <div><span>Руда</span><strong>{{ currentSceneInventory().shard_ore }}</strong></div>
          <div><span>Банк XP</span><strong>{{ currentSceneInventory().pending_xp }}</strong></div>
        </div>
      </section>

      <section class="card card--dark world-panel world-panel--wide">
        <h2>Фарм-лог</h2>
        <div v-if="world && world.farm_log?.length" class="world-log-list">
          <div v-for="(entry, index) in world.farm_log" :key="`${entry.kind || 'event'}-${entry.at || index}`" class="world-log-item">
            <strong>{{ farmLogPlayers(entry).join(" + ") }}</strong>
            <span>{{ entry.kind || "event" }} · {{ entry.target || "—" }} · {{ farmLogDuration(entry) }}</span>
          </div>
        </div>
        <p v-else class="muted">Сейчас нет совпавших праймов, поэтому фарм-лог пуст.</p>
      </section>

      <section class="card card--dark world-panel world-panel--wide">
        <h2>Чат шарда</h2>
        <div ref="chatMessagesRef" class="world-chat-list">
          <div v-for="message in chatMessages" :key="message.id" class="world-chat-item">
            <strong>{{ message.nickname }}</strong>
            <span>{{ message.content }}</span>
            <small>{{ formatDate(message.created_at) }}</small>
          </div>
          <p v-if="!chatMessages.length" class="muted">Сообщений пока нет.</p>
        </div>
        <form class="world-chat-form" @submit.prevent="sendChatMessage">
          <input
            v-model="chatDraft"
            type="text"
            maxlength="500"
            placeholder="Написать в чат шарда..."
          />
          <button class="ghost" type="submit" :disabled="!canSendChat">
            {{ chatSending ? "..." : "Отправить" }}
          </button>
        </form>
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

.legend-dot--energy {
  background: #83d8ff;
  box-shadow: 0 0 0 1px rgba(131, 216, 255, 0.25), 0 0 10px rgba(131, 216, 255, 0.18);
}

.legend-dot--ore {
  background: #d9b065;
  box-shadow: 0 0 0 1px rgba(217, 176, 101, 0.22), 0 0 10px rgba(217, 176, 101, 0.12);
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

.world-chat-list {
  max-height: 14rem;
  overflow-y: auto;
  display: grid;
  gap: var(--space-xs);
  padding-right: var(--space-2xs);
}

.world-chat-item {
  display: grid;
  gap: 0.2rem;
  padding-bottom: var(--space-2xs);
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.world-chat-item strong {
  color: var(--farmspot-text-on-dark);
  font-size: var(--step--1);
}

.world-chat-item span {
  color: var(--farmspot-text-on-dark);
}

.world-chat-item small {
  color: var(--farmspot-text-on-dark-muted);
}

.world-chat-form {
  display: flex;
  gap: var(--space-xs);
  margin-top: var(--space-xs);
}

.world-chat-form input {
  flex: 1;
  border-radius: var(--radius-m);
  border: 1px solid rgba(255, 255, 255, 0.14);
  background: rgba(255, 255, 255, 0.04);
  color: var(--farmspot-text-on-dark);
  padding: 0.55rem 0.75rem;
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
