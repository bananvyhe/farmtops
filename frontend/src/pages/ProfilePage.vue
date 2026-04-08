<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { RouterLink, useRoute, useRouter } from "vue-router"
import { api } from "../api"
import { sessionState } from "../useSession"

const DAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
const HOURS = Array.from({ length: 24 }, (_, hour) => hour)
const REFERENCE_LOCAL_MONDAY = [2026, 0, 5]
const REFERENCE_UTC_MONDAY_MS = Date.UTC(2026, 0, 5, 0, 0, 0, 0)

const loading = ref(true)
const saving = ref(false)
const error = ref("")
const success = ref("")
const selectedSlotsLocal = ref(new Set())
const dragActive = ref(false)
const dragPaintValue = ref(true)
const browserTimeZone = ref(detectTimeZone())
const profileHydrated = ref(false)
const lastSavedSignature = ref("")
const nicknameDraft = ref("")
const nicknameAvailable = ref(true)
const nicknameChecking = ref(false)
const nicknameStatus = ref("")
const nicknameStatusKind = ref("muted")
const nicknameSaving = ref(false)
const shards = ref([])
const loadingShards = ref(false)
const activeShardId = ref(null)
let autoSaveTimer = null
let nicknameCheckTimer = null
const route = useRoute()
const router = useRouter()

function detectTimeZone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
}

function formatCurrency(cents) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB" }).format((cents || 0) / 100)
}

function slotKey(dayIndex, hour) {
  return `${dayIndex}:${hour}`
}

function localSlotToUtcSlot(dayIndex, hour) {
  const localDate = new Date(REFERENCE_LOCAL_MONDAY[0], REFERENCE_LOCAL_MONDAY[1], REFERENCE_LOCAL_MONDAY[2] + dayIndex, hour, 0, 0, 0)
  const utcDayIndex = (localDate.getUTCDay() + 6) % 7
  return utcDayIndex * 24 + localDate.getUTCHours()
}

function utcSlotToLocalKey(utcSlot) {
  const utcDayIndex = Math.floor(utcSlot / 24)
  const hour = utcSlot % 24
  const localDate = new Date(REFERENCE_UTC_MONDAY_MS + ((utcDayIndex * 24 + hour) * 60 * 60 * 1000))
  const localDayIndex = (localDate.getDay() + 6) % 7
  return slotKey(localDayIndex, localDate.getHours())
}

function setSelectionFromUtcSlots(slots) {
  selectedSlotsLocal.value = new Set(Array.from(slots || []).map((slot) => utcSlotToLocalKey(Number(slot))))
}

function selectedUtcSlots() {
  return Array.from(selectedSlotsLocal.value)
    .map((key) => {
      const [dayIndex, hour] = key.split(":").map(Number)
      return localSlotToUtcSlot(dayIndex, hour)
    })
    .sort((left, right) => left - right)
}

function toggleLocalSlot(dayIndex, hour, forceValue = null) {
  const next = new Set(selectedSlotsLocal.value)
  const key = slotKey(dayIndex, hour)
  const shouldEnable = forceValue === null ? !next.has(key) : forceValue

  if (shouldEnable) next.add(key)
  else next.delete(key)

  selectedSlotsLocal.value = next
}

function onCellPointerDown(dayIndex, hour) {
  const key = slotKey(dayIndex, hour)
  dragPaintValue.value = !selectedSlotsLocal.value.has(key)
  dragActive.value = true
  toggleLocalSlot(dayIndex, hour, dragPaintValue.value)
}

function onCellPointerEnter(dayIndex, hour) {
  if (!dragActive.value) return
  toggleLocalSlot(dayIndex, hour, dragPaintValue.value)
}

function stopDragSelection() {
  dragActive.value = false
}

async function loadProfile() {
  loading.value = true
  error.value = ""

  try {
    const data = await api.profile()
    sessionState.user = data.user
    browserTimeZone.value = detectTimeZone()
    nicknameDraft.value = data.user.nickname || ""
    nicknameAvailable.value = true
    nicknameStatus.value = data.user.can_change_nickname ? "Ник можно изменить один раз." : "Ник уже менялся."
    nicknameStatusKind.value = data.user.can_change_nickname ? "muted" : "error"
    setSelectionFromUtcSlots(data.user.prime_slots_utc || [])
    lastSavedSignature.value = scheduleSignature.value
    profileHydrated.value = true
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}

async function loadShards() {
  loadingShards.value = true

  try {
    const data = await api.shards()
    shards.value = data.shards || []

    const requestedShardId = route.query.shard_id ? String(route.query.shard_id) : null
    const shardIds = new Set(shards.value.map((shard) => String(shard.id)))

    if (requestedShardId && shardIds.has(requestedShardId)) {
      activeShardId.value = requestedShardId
    } else if (!activeShardId.value || !shardIds.has(String(activeShardId.value))) {
      activeShardId.value = shards.value[0] ? String(shards.value[0].id) : null
    }
  } catch (err) {
    error.value = err.message
  } finally {
    loadingShards.value = false
  }
}

async function checkNicknameAvailability(value) {
  const nickname = value.trim().toLowerCase()

  if (!sessionState.user?.can_change_nickname) {
    nicknameAvailable.value = false
    nicknameStatus.value = "Ник уже нельзя менять."
    nicknameStatusKind.value = "error"
    return
  }

  if (!nickname) {
    nicknameAvailable.value = false
    nicknameStatus.value = "Введите ник."
    nicknameStatusKind.value = "muted"
    return
  }

  if (nickname === sessionState.user?.nickname) {
    nicknameAvailable.value = true
    nicknameStatus.value = "Это текущий ник."
    nicknameStatusKind.value = "muted"
    return
  }

  nicknameChecking.value = true
  nicknameStatus.value = "Проверяем ник..."
  nicknameStatusKind.value = "muted"

  try {
    const data = await api.checkProfileNickname(nickname)
    nicknameAvailable.value = Boolean(data.available)
    nicknameStatus.value = data.available ? "Ник свободен." : "Ник уже занят."
    nicknameStatusKind.value = data.available ? "success" : "error"
  } catch (err) {
    nicknameAvailable.value = false
    nicknameStatus.value = err.message
    nicknameStatusKind.value = "error"
  } finally {
    nicknameChecking.value = false
  }
}

async function saveNickname() {
  if (!sessionState.user?.can_change_nickname) return
  const nickname = nicknameDraft.value.trim().toLowerCase()
  if (!nickname || !nicknameAvailable.value || nickname === sessionState.user?.nickname) return

  nicknameSaving.value = true
  error.value = ""
  success.value = ""

  try {
    const data = await api.updateProfile({ nickname })
    sessionState.user = data.user
    nicknameDraft.value = data.user.nickname || nickname
    nicknameAvailable.value = true
    nicknameStatus.value = data.user.can_change_nickname ? "Ник сохранен." : "Ник сохранен. Изменить его больше нельзя."
    nicknameStatusKind.value = data.user.can_change_nickname ? "success" : "error"
  } catch (err) {
    error.value = err.message
  } finally {
    nicknameSaving.value = false
  }
}

async function saveProfile({ silent = false } = {}) {
  if (scheduleSignature.value === lastSavedSignature.value) return

  saving.value = true
  error.value = ""
  if (!silent) success.value = ""

  try {
    const data = await api.updateProfile({
      prime_time_zone: browserTimeZone.value,
      prime_slots_utc: selectedUtcSlots()
    })
    sessionState.user = data.user
    setSelectionFromUtcSlots(data.user.prime_slots_utc || [])
    lastSavedSignature.value = scheduleSignature.value
    success.value = silent ? "Изменения сохранены автоматически." : "Прайм-окна сохранены."
  } catch (err) {
    error.value = err.message
  } finally {
    saving.value = false
  }
}

const selectedLocalCount = computed(() => selectedSlotsLocal.value.size)
const selectedSlotsSignature = computed(() => selectedUtcSlots().join(","))
const scheduleSignature = computed(() => `${browserTimeZone.value}|${selectedSlotsSignature.value}`)

const utcSummary = computed(() => {
  const grouped = new Map()

  selectedUtcSlots().forEach((slot) => {
    const dayIndex = Math.floor(slot / 24)
    const hour = slot % 24
    const hours = grouped.get(dayIndex) || []
    hours.push(hour)
    grouped.set(dayIndex, hours)
  })

  return DAYS.map((day, dayIndex) => ({
    day,
    hours: (grouped.get(dayIndex) || []).sort((left, right) => left - right)
  })).filter(({ hours }) => hours.length > 0)
})

const activeShard = computed(() => shards.value.find((shard) => String(shard.id) === String(activeShardId.value)) || null)

function shardStatusLabel(status) {
  if (status === "draft") return "Черновик"
  if (status === "active") return "Активен"
  if (status === "archived") return "Архив"
  return status
}

function shardSeedShort(seed) {
  return String(seed || "").slice(0, 8)
}

function openShardWorld(shardId) {
  if (!shardId) return
  router.push(`/world/${shardId}`)
}

onMounted(() => {
  window.addEventListener("pointerup", stopDragSelection)
  Promise.resolve()
    .then(() => loadProfile())
    .then(() => loadShards())
})

onBeforeUnmount(() => {
  window.removeEventListener("pointerup", stopDragSelection)
  if (autoSaveTimer) window.clearTimeout(autoSaveTimer)
  if (nicknameCheckTimer) window.clearTimeout(nicknameCheckTimer)
})

watch(scheduleSignature, (nextValue) => {
  if (!profileHydrated.value) return
  if (nextValue === lastSavedSignature.value) return

  error.value = ""
  success.value = "Сохраняем изменения..."
  if (autoSaveTimer) window.clearTimeout(autoSaveTimer)
  autoSaveTimer = window.setTimeout(() => {
    saveProfile({ silent: true })
  }, 350)
})

watch(nicknameDraft, (nextValue) => {
  if (!profileHydrated.value) return
  if (nicknameCheckTimer) window.clearTimeout(nicknameCheckTimer)
  nicknameCheckTimer = window.setTimeout(() => {
    checkNicknameAvailability(nextValue)
  }, 250)
})
</script>

<template>
  <main class="profile-page" v-if="sessionState.user">
    <section class="card profile-hero">
      <div>
        <div class="eyebrow">профиль и прайм-окна</div>
        <h1>Профиль наблюдателя</h1>
        <p class="muted">
          Отметьте часы, когда ваш бот должен запускаться от вашего имени. Слоты сохраняются в UTC, поэтому
          пересечения между пользователями можно сравнивать напрямую и искать общие окна для будущего шарда.
        </p>
      </div>
      <div class="profile-hero__meta">
        <span class="profile-pill">Локальный часовой пояс: {{ browserTimeZone }}</span>
        <span class="profile-pill">Выбрано часов: {{ selectedLocalCount }}</span>
      </div>
    </section>

    <section class="card profile-grid-card" v-if="!loading">
      <div class="profile-grid-card__header">
        <div>
          <h2>Почасовая сетка</h2>
          <p class="muted">Клик переключает час, зажатие мыши позволяет быстро прокрасить диапазон.</p>
        </div>
        <button class="ghost" type="button" @click="selectedSlotsLocal = new Set()">Очистить</button>
      </div>

      <div class="prime-grid-wrapper">
        <div class="prime-grid">
          <div class="prime-grid__corner">Локальное время</div>
          <div v-for="day in DAYS" :key="day" class="prime-grid__day">{{ day }}</div>

          <template v-for="hour in HOURS" :key="hour">
            <div class="prime-grid__hour">{{ String(hour).padStart(2, "0") }}:00</div>
            <button
              v-for="(day, dayIndex) in DAYS"
              :key="`${day}-${hour}`"
              class="prime-grid__cell"
              :class="{ 'prime-grid__cell--active': selectedSlotsLocal.has(slotKey(dayIndex, hour)) }"
              type="button"
              @pointerdown.prevent="onCellPointerDown(dayIndex, hour)"
              @pointerenter="onCellPointerEnter(dayIndex, hour)"
            >
              <span class="sr-only">{{ day }} {{ hour }}:00</span>
            </button>
          </template>
        </div>
      </div>

      <p v-if="success" class="success">{{ success }}</p>
      <p v-if="error" class="error">{{ error }}</p>
    </section>

    <section class="card profile-shards-card" v-if="!loading">
      <div class="profile-grid-card__header">
        <div>
          <h2>Шарды</h2>
          <p class="muted">Отдельные вкладки по играм, где уже создана своя world-сессия.</p>
        </div>
      </div>

      <template v-if="loadingShards">
        <p class="muted">Загружаем шарды...</p>
      </template>
      <template v-else-if="shards.length">
        <v-tabs v-model="activeShardId" class="profile-shards-tabs" color="primary" show-arrows>
          <v-tab v-for="shard in shards" :key="shard.id" :value="String(shard.id)">
            {{ shard.game_name }}
          </v-tab>
        </v-tabs>

        <v-window v-model="activeShardId" class="profile-shard-panel">
          <v-window-item v-for="shard in shards" :key="shard.id" :value="String(shard.id)">
            <article class="profile-shard-card">
              <h3>{{ shard.name }}</h3>
              <div class="detail-list">
                <div><span>Игра</span><strong>{{ shard.game_name }}</strong></div>
                <div><span>Статус</span><strong>{{ shardStatusLabel(shard.status) }}</strong></div>
                <div><span>Seed</span><strong>{{ shardSeedShort(shard.world_seed) }}</strong></div>
                <div><span>Создан</span><strong>{{ new Date(shard.created_at).toLocaleString("ru-RU") }}</strong></div>
              </div>
            </article>
          </v-window-item>
        </v-window>
      </template>
      <p v-else class="muted">
        Пока нет созданных шардов. Нажмите «Войти в мир» на карточке игры с активными следящими.
      </p>

      <div v-if="activeShard" class="profile-shard-card profile-shard-card--summary">
        <h3>Активный шард</h3>
        <div class="detail-list">
          <div>
            <span>Игра</span>
            <strong><RouterLink :to="`/world/${activeShard.id}`" class="inline-link">{{ activeShard.game_name }}</RouterLink></strong>
          </div>
          <div>
            <span>Ник</span>
            <strong><RouterLink to="/profile#account" class="inline-link">{{ sessionState.user.nickname }}</RouterLink></strong>
          </div>
          <div><span>Статус</span><strong>{{ shardStatusLabel(activeShard.status) }}</strong></div>
          <div><span>Seed</span><strong>{{ shardSeedShort(activeShard.world_seed) }}</strong></div>
        </div>
        <button type="button" class="ghost" @click="openShardWorld(activeShard.id)">Открыть мир</button>
      </div>
    </section>

    <section class="profile-columns" v-if="!loading">
      <section id="account" class="card">
        <h2>Аккаунт</h2>
        <div class="detail-list">
          <div><span>Ник</span><strong>{{ sessionState.user.nickname }}</strong></div>
          <div><span>E-mail</span><strong>{{ sessionState.user.email }}</strong></div>
          <div><span>Роль</span><strong>{{ sessionState.user.role }}</strong></div>
          <div><span>Тариф</span><strong>{{ sessionState.user.tariff_name }}</strong></div>
          <div><span>Баланс</span><strong>{{ formatCurrency(sessionState.user.balance_cents) }}</strong></div>
          <div><span>Списание в час</span><strong>{{ formatCurrency(sessionState.user.hourly_rate_cents) }}</strong></div>
          <div><span>Уровень мира</span><strong>{{ sessionState.user.world_level }}</strong></div>
          <div><span>XP аккаунта</span><strong>{{ sessionState.user.world_xp_total }}</strong></div>
          <div><span>XP банк</span><strong>{{ sessionState.user.world_xp_bank }}</strong></div>
          <div><span>Убийств босса</span><strong>{{ sessionState.user.world_boss_kills }}</strong></div>
        </div>
        <div class="nickname-editor">
          <label>
            Никнейм
            <input
              v-model="nicknameDraft"
              type="text"
              maxlength="20"
              :disabled="!sessionState.user.can_change_nickname || nicknameSaving"
              placeholder="u_example123"
              autocomplete="off"
              spellcheck="false"
            />
          </label>
          <div class="nickname-editor__meta">
            <span :class="`nickname-status nickname-status--${nicknameStatusKind}`">{{ nicknameChecking ? "Проверяем..." : nicknameStatus }}</span>
            <button
              type="button"
              :disabled="nicknameSaving || nicknameChecking || !sessionState.user.can_change_nickname || !nicknameAvailable || nicknameDraft.trim().toLowerCase() === sessionState.user.nickname"
              @click="saveNickname"
            >
              {{ nicknameSaving ? "Сохраняем..." : "Сохранить ник" }}
            </button>
          </div>
          <p class="muted">Ник можно поменять только один раз. Доступность проверяется по мере ввода.</p>
        </div>
        <RouterLink v-if="activeShard" :to="`/world/${activeShard.id}`" class="ghost profile-dashboard-link">Открыть мир</RouterLink>
        <RouterLink to="/dashboard" class="ghost profile-dashboard-link">Платежи и история списаний</RouterLink>
      </section>

      <section class="card">
        <h2>UTC-представление</h2>
        <p class="muted">
          Эти слоты уже нормализованы в UTC. Для поиска пересечений между пользователями достаточно сравнить массивы
          `prime_slots_utc` и взять общие часы.
        </p>
        <div v-if="utcSummary.length" class="utc-summary">
          <div v-for="item in utcSummary" :key="item.day" class="utc-summary__row">
            <strong>{{ item.day }} UTC</strong>
            <span>{{ item.hours.map((hour) => `${String(hour).padStart(2, "0")}:00`).join(", ") }}</span>
          </div>
        </div>
        <p v-else class="muted">Часы еще не выбраны.</p>
      </section>
    </section>

    <section class="card" v-if="loading">
      <p class="muted">Загружаем профиль...</p>
    </section>
  </main>
</template>
