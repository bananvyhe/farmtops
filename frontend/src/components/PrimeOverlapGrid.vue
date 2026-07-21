<script setup>
import { computed } from "vue"

const props = defineProps({
  overlaps: { type: Array, default: () => [] },
  cycleDays: { type: Number, default: 7 },
  slots: { type: Array, default: () => [] }
})

const HOURS = Array.from({ length: 24 }, (_, hour) => hour)
const DAYS = 14
const slotSet = computed(() => new Set(props.slots.map(Number)))
const overlapMap = computed(() => new Map(props.overlaps.map((item) => [Number(item.slot_index), item])))
const maxCount = computed(() => Math.max(1, ...props.overlaps.map((item) => Number(item.users_count) || 0)))
const gridStyle = computed(() => ({ gridTemplateColumns: `84px repeat(${DAYS}, minmax(66px, 1fr))`, minWidth: `${84 + (DAYS * 66)}px` }))
const days = computed(() => Array.from({ length: DAYS }, (_, index) => ({
  index,
  repeated: index >= props.cycleDays,
  label: new Intl.DateTimeFormat("ru-RU", { weekday: "short", day: "2-digit", month: "2-digit" }).format(new Date(Date.now() + index * 86400000))
})))

function slot(day, hour) { return ((day % props.cycleDays) * 24) + hour }
function overlapFor(day, hour) { return overlapMap.value.get(slot(day, hour)) || null }
function styleFor(overlap) {
  if (!overlap) return null
  return { "--prime-overlap-alpha": Math.min(0.9, 0.28 + ((Number(overlap.users_count) || 1) / maxCount.value) * 0.5).toFixed(2) }
}
function titleFor(overlap, day, hour) {
  if (!overlap) return `${days.value[day].label} ${String(hour).padStart(2, "0")}:00`
  return `Совпадает ${overlap.users_count}: ${(overlap.users || []).map((user) => user.nickname).join(", ")}`
}
</script>

<template>
  <div class="profile-preview-card game-prime-preview">
    <div>
      <h3>Фантомный прогноз на 14 дней</h3>
      <p class="muted">Плотная подсветка — текущий цикл. Легкая подсветка — повтор. Зеленые ячейки — пересечения праймов этой игры.</p>
    </div>
    <div class="prime-grid-wrapper prime-grid-wrapper--preview">
      <div class="prime-grid prime-grid--preview" :style="gridStyle">
        <div class="prime-grid__corner prime-grid__corner--preview">14 дней</div>
        <div v-for="day in days" :key="day.index" class="prime-grid__day prime-grid__day--preview" :class="{ 'prime-grid__day--ghost': day.repeated }" :title="day.label">
          <strong>{{ day.label }}</strong><span>{{ day.repeated ? `Повтор ${Math.floor(day.index / cycleDays) + 1}` : `Цикл ${day.index + 1}` }}</span>
        </div>
        <template v-for="hour in HOURS" :key="hour">
          <div class="prime-grid__hour prime-grid__hour--preview">{{ String(hour).padStart(2, "0") }}</div>
          <div v-for="day in days" :key="`${day.index}-${hour}`" class="prime-grid__cell prime-grid__cell--preview" :class="{
            'prime-grid__cell--active': slotSet.has(slot(day.index, hour)) && !day.repeated,
            'prime-grid__cell--ghost': slotSet.has(slot(day.index, hour)) && day.repeated,
            'prime-grid__cell--overlap': overlapFor(day.index, hour)
          }" :style="styleFor(overlapFor(day.index, hour))" :title="titleFor(overlapFor(day.index, hour), day.index, hour)" :aria-label="titleFor(overlapFor(day.index, hour), day.index, hour)" role="img">
            <template v-if="overlapFor(day.index, hour)">
              <span class="prime-grid__overlap-count">+{{ overlapFor(day.index, hour).users_count }}</span>
              <span class="prime-grid__overlap-popover prime-grid__overlap-popover--static">
                <strong>{{ overlapFor(day.index, hour).users_count }} совпадений</strong>
                <span v-for="user in (overlapFor(day.index, hour).users || []).slice(0, 3)" :key="user.id">{{ user.nickname }}</span>
                <span v-if="(overlapFor(day.index, hour).users || []).length > 3">+ещё {{ (overlapFor(day.index, hour).users || []).length - 3 }}</span>
              </span>
            </template>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
