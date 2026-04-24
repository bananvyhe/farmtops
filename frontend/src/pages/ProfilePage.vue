<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { RouterLink, useRoute, useRouter } from "vue-router"
import { api } from "../api"
import { sessionState } from "../useSession"

const HOURS = Array.from({ length: 24 }, (_, hour) => hour)
const MAX_CYCLE_DAYS = 14
const REFERENCE_UTC_MONDAY_MS = Date.UTC(2026, 0, 5, 0, 0, 0, 0)

const loading = ref(true)
const saving = ref(false)
const error = ref("")
const success = ref("")
const selectedCycleSlots = ref(new Set())
const cycleDays = ref(1)
const dragActive = ref(false)
const dragPaintValue = ref(true)
const browserTimeZone = ref(detectTimeZone())
const displayAnchorIso = ref(todayIso())
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
const primeGridWrapperRef = ref(null)
let autoSaveTimer = null
let nicknameCheckTimer = null
let primeGridScrollTimer = null
const route = useRoute()
const router = useRouter()

function detectTimeZone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
}

function todayLocalDate() {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
}

function todayIso() {
  return dateToIso(todayLocalDate())
}

function dateToIso(date) {
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, "0"), String(date.getDate()).padStart(2, "0")].join("-")
}

function parseIsoDate(value) {
  if (!value) return null
  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!match) return null

  const [, year, month, day] = match
  return new Date(Number(year), Number(month) - 1, Number(day))
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

function dayStamp(date) {
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())
}

function diffCalendarDays(left, right) {
  return Math.round((dayStamp(left) - dayStamp(right)) / 86400000)
}

function mod(value, base) {
  return ((value % base) + base) % base
}

function weekdayIndexMonday(date) {
  return (date.getDay() + 6) % 7
}

function weekdayShort(date) {
  const label = new Intl.DateTimeFormat("ru-RU", { weekday: "short" }).format(date)
  return label.slice(0, 1).toUpperCase() + label.slice(1).replace(".", "")
}

function formatDayLabel(date) {
  return `${weekdayShort(date)} ${new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "2-digit" }).format(date)}`
}

function formatDayTitle(date) {
  return new Intl.DateTimeFormat("ru-RU", { weekday: "long", day: "numeric", month: "long" }).format(date)
}

function formatUtcDateTime(date) {
  return new Intl.DateTimeFormat("ru-RU", {
    timeZone: "UTC",
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date)
}

function clampCycleDays(value) {
  const days = Number(value) || 1
  return Math.min(MAX_CYCLE_DAYS, Math.max(1, days))
}

function cycleSlotIndex(dayIndex, hour) {
  return (dayIndex * 24) + hour
}

function normalizeCycleSlots(slots, days) {
  const maxSlot = clampCycleDays(days) * 24
  return Array.from(new Set(Array.from(slots || []).map((slot) => Number(slot)).filter((slot) => Number.isInteger(slot) && slot >= 0 && slot < maxSlot))).sort((left, right) => left - right)
}

function utcSlotToLocalCycleSlot(utcSlot, todayWeekdayIndex) {
  const utcDayIndex = Math.floor(utcSlot / 24)
  const hour = utcSlot % 24
  const localDate = new Date(REFERENCE_UTC_MONDAY_MS + ((utcDayIndex * 24 + hour) * 60 * 60 * 1000))
  const localDayIndex = weekdayIndexMonday(localDate)
  const rotatedDayIndex = mod(localDayIndex - todayWeekdayIndex, 7)
  return cycleSlotIndex(rotatedDayIndex, localDate.getHours())
}

function setSelectionFromCycle(days, slots, anchorIso) {
  const normalizedDays = clampCycleDays(days)
  const today = todayLocalDate()
  const todayIsoValue = dateToIso(today)
  const sourceAnchor = parseIsoDate(anchorIso) || today
  const shift = mod(diffCalendarDays(today, sourceAnchor), normalizedDays)
  const next = new Set()

  normalizeCycleSlots(slots, normalizedDays).forEach((slot) => {
    const sourceDayIndex = Math.floor(slot / 24)
    const hour = slot % 24
    const rotatedDayIndex = mod(sourceDayIndex - shift, normalizedDays)
    next.add(cycleSlotIndex(rotatedDayIndex, hour))
  })

  cycleDays.value = normalizedDays
  selectedCycleSlots.value = next
  displayAnchorIso.value = todayIsoValue
}

function setSelectionFromLegacyUtc(slots) {
  const todayWeekdayIndex = weekdayIndexMonday(todayLocalDate())
  cycleDays.value = 7
  selectedCycleSlots.value = new Set(Array.from(slots || []).map((slot) => utcSlotToLocalCycleSlot(Number(slot), todayWeekdayIndex)))
  displayAnchorIso.value = todayIso()
}

function hydrateSchedule(user) {
  const nextCycleDays = clampCycleDays(user?.prime_cycle_days || 7)
  const cycleSlots = Array.isArray(user?.prime_cycle_slots_local) && user.prime_cycle_slots_local.length
    ? user.prime_cycle_slots_local
    : null

  if (cycleSlots) {
    setSelectionFromCycle(nextCycleDays, cycleSlots, user?.prime_cycle_anchor_on)
    return
  }

  setSelectionFromLegacyUtc(user?.prime_slots_utc || [])
}

function selectedCycleSlotsArray() {
  return normalizeCycleSlots(selectedCycleSlots.value, cycleDays.value)
}

function toggleCycleSlot(dayIndex, hour, forceValue = null) {
  const next = new Set(selectedCycleSlots.value)
  const slot = cycleSlotIndex(dayIndex, hour)
  const shouldEnable = forceValue === null ? !next.has(slot) : forceValue

  if (shouldEnable) next.add(slot)
  else next.delete(slot)

  selectedCycleSlots.value = next
}

function onCellPointerDown(dayIndex, hour) {
  const slot = cycleSlotIndex(dayIndex, hour)
  dragPaintValue.value = !selectedCycleSlots.value.has(slot)
  dragActive.value = true
  toggleCycleSlot(dayIndex, hour, dragPaintValue.value)
}

function onCellPointerEnter(dayIndex, hour) {
  if (!dragActive.value) return
  toggleCycleSlot(dayIndex, hour, dragPaintValue.value)
}

function stopDragSelection() {
  dragActive.value = false
}

function changeCycleDays(delta) {
  const nextDays = clampCycleDays(cycleDays.value + delta)
  if (nextDays === cycleDays.value) return

  cycleDays.value = nextDays
  selectedCycleSlots.value = new Set(selectedCycleSlotsArray().filter((slot) => slot < nextDays * 24))
}

function clearCycle() {
  selectedCycleSlots.value = new Set()
}

function nudgePrimeGrid(left, top, behavior = "smooth") {
  if (!primeGridWrapperRef.value) return
  primeGridWrapperRef.value.scrollBy({ left, top, behavior })
}

function startPrimeGridScroll(left, top) {
  stopPrimeGridScroll()
  nudgePrimeGrid(left, top)
  primeGridScrollTimer = window.setInterval(() => {
    nudgePrimeGrid(left, top, "auto")
  }, 140)
}

function stopPrimeGridScroll() {
  if (!primeGridScrollTimer) return
  window.clearInterval(primeGridScrollTimer)
  primeGridScrollTimer = null
}

function formatCurrency(cents) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB" }).format((cents || 0) / 100)
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
    hydrateSchedule(data.user)
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
      prime_cycle_days: cycleDays.value,
      prime_cycle_anchor_on: displayAnchorIso.value,
      prime_cycle_slots_local: selectedCycleSlotsArray()
    })
    sessionState.user = data.user
    hydrateSchedule(data.user)
    lastSavedSignature.value = scheduleSignature.value
    success.value = silent ? "Изменения сохранены автоматически." : "Прайм-цикл сохранен."
  } catch (err) {
    error.value = err.message
  } finally {
    saving.value = false
  }
}

const selectedLocalCount = computed(() => selectedCycleSlots.value.size)
const selectedSlotsSignature = computed(() => selectedCycleSlotsArray().join(","))
const scheduleSignature = computed(() => `${browserTimeZone.value}|${displayAnchorIso.value}|${cycleDays.value}|${selectedSlotsSignature.value}`)

const visibleCycleDays = computed(() => {
  const start = parseIsoDate(displayAnchorIso.value) || todayLocalDate()

  return Array.from({ length: cycleDays.value }, (_, offset) => {
    const date = addDays(start, offset)
    return {
      index: offset,
      date,
      shortLabel: formatDayLabel(date),
      title: formatDayTitle(date),
      cycleLabel: offset === 0 ? "Сегодня" : `День ${offset + 1}`
    }
  })
})

const upcomingPreviewDays = computed(() => {
  const start = parseIsoDate(displayAnchorIso.value) || todayLocalDate()

  return Array.from({ length: MAX_CYCLE_DAYS }, (_, offset) => {
    const date = addDays(start, offset)
    return {
      index: offset,
      date,
      cycleIndex: mod(offset, cycleDays.value),
      repeated: offset >= cycleDays.value,
      shortLabel: formatDayLabel(date),
      title: formatDayTitle(date)
    }
  })
})

const editorGridStyle = computed(() => ({
  gridTemplateColumns: `96px repeat(${cycleDays.value}, minmax(92px, 1fr))`,
  minWidth: `${96 + (cycleDays.value * 92)}px`
}))

const previewGridStyle = computed(() => ({
  gridTemplateColumns: `84px repeat(${MAX_CYCLE_DAYS}, minmax(66px, 1fr))`,
  minWidth: `${84 + (MAX_CYCLE_DAYS * 66)}px`
}))

const cycleSummary = computed(() => {
  if (!selectedLocalCount.value) return "Часы в цикле еще не выбраны."
  return `В цикле ${cycleDays.value} ${cycleDays.value === 1 ? "день" : cycleDays.value < 5 ? "дня" : "дней"} и ${selectedLocalCount.value} активных часов.`
})

const utcSummary = computed(() => {
  const grouped = new Map()
  const start = parseIsoDate(displayAnchorIso.value) || todayLocalDate()

  upcomingPreviewDays.value.slice(0, 7).forEach((day) => {
    HOURS.forEach((hour) => {
      if (!selectedCycleSlots.value.has(cycleSlotIndex(day.cycleIndex, hour))) return

      const localDate = new Date(start.getFullYear(), start.getMonth(), start.getDate() + day.index, hour, 0, 0, 0)
      const utcDate = new Date(localDate.getTime() + (localDate.getTimezoneOffset() * 60000))
      const key = dateToIso(new Date(utcDate.getUTCFullYear(), utcDate.getUTCMonth(), utcDate.getUTCDate()))
      const hours = grouped.get(key) || []
      hours.push(formatUtcDateTime(localDate))
      grouped.set(key, hours)
    })
  })

  return Array.from(grouped.entries()).map(([date, labels]) => ({ date, labels }))
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
  stopPrimeGridScroll()
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
          Цикл теперь строится от текущего локального дня. Вы выбираете первый день и добавляете следующие дни цикла,
          а ниже сразу видно, как этот узор повторится на 14 суток вперед.
        </p>
      </div>
      <div class="profile-hero__meta">
        <span class="profile-pill">Локальный часовой пояс: {{ browserTimeZone }}</span>
        <span class="profile-pill">Длина цикла: {{ cycleDays }} дн.</span>
        <span class="profile-pill">Выбрано часов: {{ selectedLocalCount }}</span>
      </div>
    </section>

    <section class="card profile-grid-card" v-if="!loading">
      <div class="profile-grid-card__header">
        <div>
          <h2>Почасовой цикл</h2>
          <p class="muted">
            Первый столбец всегда означает сегодня. Добавляйте дни до 14, а фантомная сетка ниже покажет повторение цикла.
          </p>
        </div>
        <div class="profile-grid-card__actions">
          <button class="ghost" type="button" :disabled="cycleDays <= 1" @click="changeCycleDays(-1)">− день</button>
          <button class="ghost" type="button" :disabled="cycleDays >= MAX_CYCLE_DAYS" @click="changeCycleDays(1)">+ день</button>
          <button class="ghost" type="button" @click="clearCycle">Очистить</button>
        </div>
      </div>

      <div class="profile-cycle-summary">
        <strong>{{ cycleSummary }}</strong>
        <span class="muted">Сохранение идет автоматически. Текущий день всегда пересобирается первым при новом заходе в профиль.</span>
      </div>

      <div ref="primeGridWrapperRef" class="prime-grid-wrapper">
        <div class="prime-grid prime-grid--editor" :style="editorGridStyle">
          <div class="prime-grid__corner">Локальное время</div>
          <div v-for="day in visibleCycleDays" :key="day.index" class="prime-grid__day prime-grid__day--editor" :title="day.title">
            <strong>{{ day.shortLabel }}</strong>
            <span>{{ day.cycleLabel }}</span>
          </div>

          <template v-for="hour in HOURS" :key="hour">
            <div class="prime-grid__hour">{{ String(hour).padStart(2, "0") }}:00</div>
            <button
              v-for="day in visibleCycleDays"
              :key="`${day.index}-${hour}`"
              class="prime-grid__cell"
              :class="{ 'prime-grid__cell--active': selectedCycleSlots.has(cycleSlotIndex(day.index, hour)) }"
              type="button"
              @pointerdown.prevent="onCellPointerDown(day.index, hour)"
              @pointerenter="onCellPointerEnter(day.index, hour)"
            >
              <span class="sr-only">{{ day.shortLabel }} {{ hour }}:00</span>
            </button>
          </template>
        </div>

        <div class="prime-grid-pad" aria-label="Навигация по сетке расписания">
          <button
            type="button"
            class="prime-grid-pad__button prime-grid-pad__button--up"
            aria-label="Прокрутить вверх"
            @pointerdown.prevent="startPrimeGridScroll(0, -132)"
            @pointerup="stopPrimeGridScroll"
            @pointerleave="stopPrimeGridScroll"
            @pointercancel="stopPrimeGridScroll"
            @click="nudgePrimeGrid(0, -132)"
          >
            ↑
          </button>
          <button
            type="button"
            class="prime-grid-pad__button prime-grid-pad__button--left"
            aria-label="Прокрутить влево"
            @pointerdown.prevent="startPrimeGridScroll(-160, 0)"
            @pointerup="stopPrimeGridScroll"
            @pointerleave="stopPrimeGridScroll"
            @pointercancel="stopPrimeGridScroll"
            @click="nudgePrimeGrid(-160, 0)"
          >
            ←
          </button>
          <button
            type="button"
            class="prime-grid-pad__button prime-grid-pad__button--right"
            aria-label="Прокрутить вправо"
            @pointerdown.prevent="startPrimeGridScroll(160, 0)"
            @pointerup="stopPrimeGridScroll"
            @pointerleave="stopPrimeGridScroll"
            @pointercancel="stopPrimeGridScroll"
            @click="nudgePrimeGrid(160, 0)"
          >
            →
          </button>
          <button
            type="button"
            class="prime-grid-pad__button prime-grid-pad__button--down"
            aria-label="Прокрутить вниз"
            @pointerdown.prevent="startPrimeGridScroll(0, 132)"
            @pointerup="stopPrimeGridScroll"
            @pointerleave="stopPrimeGridScroll"
            @pointercancel="stopPrimeGridScroll"
            @click="nudgePrimeGrid(0, 132)"
          >
            ↓
          </button>
        </div>
      </div>

      <div class="profile-preview-card">
        <div>
          <h3>Фантомный прогноз на 14 дней</h3>
          <p class="muted">Плотная подсветка — текущий цикл. Легкая подсветка — повтор этого же часа на следующих днях.</p>
        </div>

        <div class="prime-grid-wrapper prime-grid-wrapper--preview">
          <div class="prime-grid prime-grid--preview" :style="previewGridStyle">
            <div class="prime-grid__corner prime-grid__corner--preview">14 дней</div>
            <div
              v-for="day in upcomingPreviewDays"
              :key="`preview-${day.index}`"
              class="prime-grid__day prime-grid__day--preview"
              :class="{ 'prime-grid__day--ghost': day.repeated }"
              :title="day.title"
            >
              <strong>{{ day.shortLabel }}</strong>
              <span>{{ day.repeated ? `Повтор ${Math.floor(day.index / cycleDays) + 1}` : `Цикл ${day.index + 1}` }}</span>
            </div>

            <template v-for="hour in HOURS" :key="`preview-hour-${hour}`">
              <div class="prime-grid__hour prime-grid__hour--preview">{{ String(hour).padStart(2, "0") }}</div>
              <div
                v-for="day in upcomingPreviewDays"
                :key="`preview-${day.index}-${hour}`"
                class="prime-grid__cell prime-grid__cell--preview"
                :class="{
                  'prime-grid__cell--active': selectedCycleSlots.has(cycleSlotIndex(day.cycleIndex, hour)) && !day.repeated,
                  'prime-grid__cell--ghost': selectedCycleSlots.has(cycleSlotIndex(day.cycleIndex, hour)) && day.repeated
                }"
              />
            </template>
          </div>
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
          <div><span>До следующего уровня</span><strong>{{ sessionState.user.world_xp_to_next_level }}</strong></div>
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
        <h2>UTC-прогноз</h2>
        <p class="muted">
          Здесь видно, как ближайшие 7 суток будут выглядеть в UTC после применения текущего цикла и вашего локального часового пояса.
        </p>
        <div v-if="utcSummary.length" class="utc-summary">
          <div v-for="item in utcSummary" :key="item.date" class="utc-summary__row">
            <strong>{{ item.date }} UTC</strong>
            <span>{{ item.labels.join(", ") }}</span>
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
