<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { useIntersectionObserver, useWindowScroll, watchThrottled } from "@vueuse/core"
import { api } from "../api"
import { useNewsUiStore } from "../stores/newsUi"

const articles = ref([])
const sources = ref([])
const sections = ref([])
const loading = ref(false)
const loadingMore = ref(false)
const error = ref("")
const selectedSourceId = ref(null)
const selectedSectionId = ref(null)
const nextCursor = ref(null)
const hasMore = ref(true)
const sentinel = ref(null)
const hydrated = ref(false)
const activeQueryKey = ref("")
const articleRefs = new Map()
const readTimers = new Map()
const pendingReadIds = new Set()
const READ_VISIBILITY_RATIO = 0.75
const READ_VISIBILITY_MS = 1000
let readObserver = null
let flushTimer = null
let requestToken = 0
const route = useRoute()
const router = useRouter()
const newsUi = useNewsUiStore()
const { y: scrollY } = useWindowScroll()

function parseQueryId(value) {
  if (Array.isArray(value)) value = value[0]
  if (value === null || value === undefined || value === "") return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function filtersFromRoute() {
  return {
    sourceId: parseQueryId(route.query.source_id),
    sectionId: parseQueryId(route.query.section_id)
  }
}

function routeQueryForFilters() {
  const query = {}
  if (selectedSourceId.value !== null && selectedSourceId.value !== undefined) query.source_id = String(selectedSourceId.value)
  if (selectedSectionId.value !== null && selectedSectionId.value !== undefined) query.section_id = String(selectedSectionId.value)
  return query
}

async function syncRouteQuery() {
  const nextQuery = routeQueryForFilters()
  const currentQuery = {
    ...(route.query.source_id ? { source_id: String(route.query.source_id) } : {}),
    ...(route.query.section_id ? { section_id: String(route.query.section_id) } : {})
  }

  if (JSON.stringify(nextQuery) === JSON.stringify(currentQuery)) return

  await router.replace({ path: "/news", query: nextQuery })
}

const sourceItems = computed(() => [
  { title: "Все источники", value: null },
  ...sources.value.map((source) => ({ title: source.name, value: source.id }))
])

const sectionItems = computed(() => {
  const filtered = sections.value.filter((section) => {
    if (selectedSourceId.value && section.news_source_id !== selectedSourceId.value) return false
    return true
  })

  return [
    { title: "Все разделы", value: null },
    ...filtered.map((section) => ({ title: `${section.name} · ${section.source_name}`, value: section.id }))
  ]
})

const formatDate = (value) => {
  if (!value) return "—"
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(new Date(value))
}

function captureFeedSnapshot() {
  return {
    filterKey: `${selectedSourceId.value ?? ""}:${selectedSectionId.value ?? ""}`,
    articles: articles.value,
    sources: sources.value,
    sections: sections.value,
    selectedSourceId: selectedSourceId.value,
    selectedSectionId: selectedSectionId.value,
    nextCursor: nextCursor.value,
    hasMore: hasMore.value,
    scrollY: scrollY.value,
    savedAt: Date.now()
  }
}

function saveFeedSnapshot() {
  newsUi.saveFeedSnapshot(captureFeedSnapshot())
}

function restoreFeedSnapshot() {
  const state = newsUi.feedSnapshot
  const routeKey = `${filtersFromRoute().sourceId ?? ""}:${filtersFromRoute().sectionId ?? ""}`

  if (!state || state.filterKey !== routeKey || !Array.isArray(state.articles) || !state.articles.length) {
    return false
  }

  articles.value = state.articles
  sources.value = state.sources || []
  sections.value = state.sections || []
  selectedSourceId.value = state.selectedSourceId ?? null
  selectedSectionId.value = state.selectedSectionId ?? null
  nextCursor.value = state.nextCursor || null
  hasMore.value = Boolean(state.hasMore)
  loading.value = false
  loadingMore.value = false

  nextTick(() => {
    window.requestAnimationFrame(() => {
      window.scrollTo({ top: state.scrollY || 0, behavior: "auto" })
    })
  })

  return true
}

function setArticleRef(articleId, element) {
  if (element) {
    articleRefs.set(articleId, element)
    if (readObserver) readObserver.observe(element)
    return
  }

  articleRefs.delete(articleId)
}

function syncReadObserver() {
  if (!readObserver) return

  readObserver.disconnect()
  articleRefs.forEach((element) => {
    if (element) readObserver.observe(element)
  })
}

function clearReadTimer(articleId) {
  const timer = readTimers.get(articleId)
  if (timer) window.clearTimeout(timer)
  readTimers.delete(articleId)
}

function resetReadTracking() {
  readTimers.forEach((timer) => window.clearTimeout(timer))
  readTimers.clear()
  pendingReadIds.clear()
  if (flushTimer) window.clearTimeout(flushTimer)
  flushTimer = null
}

function isArticleAlreadyRead(articleId) {
  return articles.value.some((article) => article.id === articleId && article.read)
}

function queueRead(articleId) {
  if (isArticleAlreadyRead(articleId)) return
  if (pendingReadIds.has(articleId)) return

  pendingReadIds.add(articleId)
  if (flushTimer) return

  flushTimer = window.setTimeout(flushReadQueue, 400)
}

async function flushReadQueue() {
  flushTimer = null
  const ids = Array.from(pendingReadIds)
  if (!ids.length) return

  pendingReadIds.clear()
  try {
    const data = await api.markNewsReads({ article_ids: ids })
    const readIds = new Set(data.read_article_ids || ids)
    articles.value = articles.value.map((article) =>
      readIds.has(article.id) ? { ...article, read: true } : article
    )
    saveFeedSnapshot()
  } catch (err) {
    ids.forEach((id) => pendingReadIds.add(id))
    if (!flushTimer) flushTimer = window.setTimeout(flushReadQueue, 1200)
  }
}

function markVisibleArticle(articleId) {
  if (isArticleAlreadyRead(articleId)) return

  clearReadTimer(articleId)
  const timer = window.setTimeout(() => {
    readTimers.delete(articleId)
    queueRead(articleId)
  }, READ_VISIBILITY_MS)
  readTimers.set(articleId, timer)
}

function markHiddenArticle(articleId) {
  clearReadTimer(articleId)
}

function isUnread(article) {
  return !article.read
}

async function loadFeed() {
  const queryKey = `${selectedSourceId.value ?? ""}:${selectedSectionId.value ?? ""}`
  const currentToken = ++requestToken
  activeQueryKey.value = queryKey
  loading.value = true
  loadingMore.value = false
  error.value = ""
  resetReadTracking()
  articles.value = []
  nextCursor.value = null
  hasMore.value = true

  try {
    const data = await api.news({
      source_id: selectedSourceId.value,
      section_id: selectedSectionId.value,
      limit: 20
    })
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return
    articles.value = data.articles
    sources.value = data.sources
    sections.value = data.sections
    nextCursor.value = data.next_cursor || null
    hasMore.value = Boolean(data.has_more)

    if (selectedSectionId.value && !sectionItems.value.some((item) => item.value === selectedSectionId.value)) {
      selectedSectionId.value = null
    }
    saveFeedSnapshot()
  } catch (err) {
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return
    error.value = err.message
  } finally {
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return
    loading.value = false
  }
}

async function loadMore() {
  if (!hasMore.value || loading.value || loadingMore.value || !nextCursor.value) return

  const currentToken = requestToken
  const queryKey = activeQueryKey.value
  loadingMore.value = true
  error.value = ""

  try {
    const data = await api.news({
      source_id: selectedSourceId.value,
      section_id: selectedSectionId.value,
      limit: 20,
      cursor: nextCursor.value
    })
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return

    const existingIds = new Set(articles.value.map((article) => article.id))
    const incoming = data.articles.filter((article) => !existingIds.has(article.id))
    articles.value = [...articles.value, ...incoming]
    nextCursor.value = data.next_cursor || null
    hasMore.value = Boolean(data.has_more)
  } catch (err) {
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return
    error.value = err.message
  } finally {
    if (currentToken !== requestToken || activeQueryKey.value !== queryKey) return
    loadingMore.value = false
  }
}

const articlePath = (article) => `/news/${article.id}`

watch(
  () => articles.value.map((article) => article.id).join(","),
  async () => {
  if (!hydrated.value) return
    await nextTick()
    syncReadObserver()
  }
)

watch(
  () => articles.value,
  () => {
    if (!hydrated.value) return
  },
  { deep: true }
)

watchThrottled(
  scrollY,
  () => {
    if (!hydrated.value) return
    saveFeedSnapshot()
  },
  { throttle: 250, trailing: true }
)

watch([selectedSourceId, selectedSectionId], () => {
  if (!hydrated.value) return

  if (selectedSectionId.value && sectionItems.value.every((item) => item.value !== selectedSectionId.value)) {
    selectedSectionId.value = null
    return
  }

  if (typeof window !== "undefined") {
    window.scrollTo({ top: 0, behavior: "auto" })
  }

  syncRouteQuery()
  loadFeed()
})

useIntersectionObserver(
  sentinel,
  ([entry]) => {
    if (entry?.isIntersecting) loadMore()
  },
  { threshold: 0.1 }
)

onMounted(async () => {
  if (typeof IntersectionObserver === "function") {
    readObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          const articleId = Number(entry.target?.dataset?.articleId)
          if (!Number.isFinite(articleId)) return

          if (entry.isIntersecting && entry.intersectionRatio >= READ_VISIBILITY_RATIO) {
            markVisibleArticle(articleId)
          } else {
            markHiddenArticle(articleId)
          }
        })
      },
      {
        threshold: [0, 0.25, READ_VISIBILITY_RATIO, 0.9]
      }
    )
  }

  const initialFilters = filtersFromRoute()
  selectedSourceId.value = initialFilters.sourceId
  selectedSectionId.value = initialFilters.sectionId

  hydrated.value = true
  if (!restoreFeedSnapshot()) {
    window.scrollTo({ top: 0, behavior: "auto" })
    await loadFeed()
  } else {
    await nextTick()
    syncReadObserver()
  }
})

onBeforeUnmount(() => {
  resetReadTracking()
  readObserver?.disconnect()
  saveFeedSnapshot()
})
</script>

<template>
  <main class="news-page">
    <section class="news-hero">
      <div class="news-hero__eyebrow">отслеживание проектов:</div>
      <span class="topbar">
      <h1 >Сбор группы</h1></span>
      <p>Далекие контуры в туманностях кажутся спящими башнями, но едва разум касается предела дозволенного — и древние пробуждаются, чтобы дать понять: в бесконечности нет места тем, кто считает себя исходной точкой.</p>
    </section>

    <section class="news-filters card">
      <div class="news-filters__grid">
        <v-select
          v-model="selectedSourceId"
          :items="sourceItems"
          item-title="title"
          item-value="value"
          label="Источник"
          variant="outlined"
          density="comfortable"
          hide-details
        />
        <v-select
          v-model="selectedSectionId"
          :items="sectionItems"
          item-title="title"
          item-value="value"
          label="Раздел"
          variant="outlined"
          density="comfortable"
          hide-details
        />
        <v-btn color="primary" size="large" variant="flat" @click="loadFeed">Обновить</v-btn>
      </div>
    </section>

    <section v-if="loading" class="news-feed">
      <article v-for="index in 4" :key="index" class="news-card card">
          <v-skeleton-loader type="image, article, button" />
        </article>
      </section>

    <section v-else class="news-feed">
      <article
        v-for="article in articles"
        :key="article.id"
        :ref="(element) => setArticleRef(article.id, element)"
        :data-article-id="article.id"
        class="news-card card"
        :class="{ 'news-card--unread': isUnread(article) }"
      >
        <div class="news-card__media">
          <img
            v-if="article.image_url"
            :src="article.image_url"
            :alt="article.title || article.preview_text || 'news image'"
          >
          <div v-else class="news-card__placeholder">
            <span>NEWS</span>
          </div>
        </div>

        <div class="news-card__body">
          <div class="news-card__meta">
            <v-chip size="small" variant="flat" color="primary">{{ article.source_name }}</v-chip>
            <v-chip size="small" variant="outlined">{{ article.section_name }}</v-chip>
            <span class="news-card__time">{{ formatDate(article.published_at || article.fetched_at) }}</span>
            <span v-if="isUnread(article)" class="news-card__badge">Новая</span>
          </div>

          <RouterLink class="news-card__title" :to="{ path: articlePath(article), query: routeQueryForFilters() }">
            <h2>{{ article.title }}</h2>
          </RouterLink>
          <p class="news-card__preview">{{ article.preview_text || article.body_text }}</p>

          <div class="news-card__actions">
            <RouterLink class="news-card__link" :to="{ path: articlePath(article), query: routeQueryForFilters() }">Читать полностью</RouterLink>
            <a :href="article.canonical_url" target="_blank" rel="noreferrer">Открыть источник</a>
          </div>
        </div>
      </article>

      <div v-if="hasMore" ref="sentinel" class="news-sentinel" aria-hidden="true" role="presentation">
        <v-progress-linear v-if="loadingMore" indeterminate color="primary" />
      </div>
    </section>

    <section v-if="!loading && !articles.length" class="news-empty card">
      <h2>Ничего не найдено</h2>
      <p>Попробуйте другой источник или раздел.</p>
    </section>

    <p v-if="error" class="news-error">{{ error }}</p>
  </main>
</template>

<style scoped>
.news-page {
  min-height: calc(100vh - 120px);
  margin-top: 8px;
  padding-bottom: 40px;
}

.news-hero {
  margin-bottom: 22px;
  padding: 20px 22px;
  border-left: 4px solid var(--farmspot-primary);
  background: rgba(14, 14, 14, 0.94);
  color: #e7e5e5;
}

.news-hero__eyebrow {
  margin-bottom: 8px;
  text-transform: uppercase;
  letter-spacing: 0.22em;
  font-size: 0.72rem;
  color: #9c9ea0;
}

.news-hero h1 {
  margin: 0 0 10px;
  font-size: clamp(1.9rem, 5vw, 3.2rem);
  letter-spacing: -0.04em;
  text-transform: uppercase;
}

.news-hero p {
  margin: 0;
  max-width: 62ch;
  color: #acabaa;
}

.news-filters {
  background: rgba(25, 26, 26, 0.94);
  color: #e7e5e5;
  margin-bottom: 22px;
}

.news-filters__grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
  gap: 14px;
  align-items: center;
}

.news-feed {
  display: grid;
  gap: 14px;
}

.news-card {
  display: grid;
  grid-template-columns: 240px minmax(0, 1fr);
  gap: 0;
  overflow: hidden;
  padding: 0;
  background: #191a1a;
  color: #e7e5e5;
  border-radius: 28px;
  transition:
    background-color 180ms ease,
    box-shadow 180ms ease,
    transform 180ms ease;
}

.news-card--unread {
  background: linear-gradient(180deg, rgba(43, 26, 17, 0.98), rgba(24, 17, 13, 0.98));
  box-shadow:
    0 0 0 1px rgba(199, 89, 35, 0.62),
    0 0 0 6px rgba(199, 89, 35, 0.09),
    0 20px 38px rgba(0, 0, 0, 0.34);
}

.news-card--unread:hover {
  transform: translateY(-1px);
}

.news-card__media {
  min-height: 180px;
  background: #252626;
}

.news-card__media img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.news-card__placeholder {
  height: 100%;
  display: grid;
  place-items: center;
  color: #9c9ea0;
  letter-spacing: 0.2em;
  font-weight: 800;
}

.news-card__body {
  padding: 18px 18px 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.news-card__meta {
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}

.news-card__time {
  color: #9c9ea0;
  font-size: 0.82rem;
}

.news-card__badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.28rem 0.72rem;
  border-radius: 999px;
  background: rgba(199, 89, 35, 0.18);
  border: 1px solid rgba(199, 89, 35, 0.48);
  color: #ffceb9;
  font-size: 0.72rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.news-card__title {
  color: inherit;
  text-decoration: none;
}

.news-card__title h2 {
  margin: 0;
  font-size: clamp(1.05rem, 2vw, 1.5rem);
  letter-spacing: -0.03em;
  line-height: 1.1;
}

.news-card__preview {
  margin: 0;
  color: #acabaa;
  line-height: 1.55;
  display: -webkit-box;
  -webkit-line-clamp: 4;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.news-card__actions {
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
  margin-top: auto;
}

.news-card__link {
  color: #93cdfc;
  text-decoration: none;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  font-size: 0.85rem;
}

.news-card__actions a {
  color: #93cdfc;
  text-decoration: none;
  font-size: 0.85rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
}

.news-empty,
.news-error {
  margin-top: 16px;
}

.news-empty {
  background: rgba(25, 26, 26, 0.94);
  color: #e7e5e5;
}

.news-error {
  color: #ee7d77;
}

.news-sentinel {
  min-height: 48px;
  display: flex;
  align-items: center;
}

@media (max-width: 900px) {
  .news-filters__grid,
  .news-card {
    grid-template-columns: 1fr;
  }

  .news-card__media {
    min-height: 220px;
  }
}
</style>
