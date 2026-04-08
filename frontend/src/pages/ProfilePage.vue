<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { RouterLink } from "vue-router"
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
let autoSaveTimer = null
let nicknameCheckTimer = null

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

onMounted(() => {
  window.addEventListener("pointerup", stopDragSelection)
  loadProfile()
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

    <section class="profile-columns" v-if="!loading">
      <section class="card">
        <h2>Аккаунт</h2>
        <div class="detail-list">
          <div><span>Ник</span><strong>{{ sessionState.user.nickname }}</strong></div>
          <div><span>E-mail</span><strong>{{ sessionState.user.email }}</strong></div>
          <div><span>Роль</span><strong>{{ sessionState.user.role }}</strong></div>
          <div><span>Тариф</span><strong>{{ sessionState.user.tariff_name }}</strong></div>
          <div><span>Баланс</span><strong>{{ formatCurrency(sessionState.user.balance_cents) }}</strong></div>
          <div><span>Списание в час</span><strong>{{ formatCurrency(sessionState.user.hourly_rate_cents) }}</strong></div>
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
