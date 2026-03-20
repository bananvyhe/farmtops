<script setup>
import { computed, onMounted, ref, watch } from "vue"
import { api } from "../api"

const articles = ref([])
const sources = ref([])
const sections = ref([])
const loading = ref(false)
const error = ref("")
const selectedSourceId = ref(null)
const selectedSectionId = ref(null)
let requestToken = 0

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

async function loadFeed() {
  const currentToken = ++requestToken
  loading.value = true
  error.value = ""

  try {
    const data = await api.news({
      source_id: selectedSourceId.value,
      section_id: selectedSectionId.value,
      limit: 100
    })
    if (currentToken !== requestToken) return
    articles.value = data.articles
    sources.value = data.sources
    sections.value = data.sections

    if (selectedSectionId.value && !sectionItems.value.some((item) => item.value === selectedSectionId.value)) {
      selectedSectionId.value = null
    }
  } catch (err) {
    if (currentToken !== requestToken) return
    error.value = err.message
  } finally {
    if (currentToken !== requestToken) return
    loading.value = false
  }
}

const articlePath = (article) => `/news/${article.id}`

watch(selectedSourceId, () => {
  if (selectedSectionId.value && sectionItems.value.every((item) => item.value !== selectedSectionId.value)) {
    selectedSectionId.value = null
  }
  loadFeed()
})

watch(selectedSectionId, () => {
  loadFeed()
})

onMounted(loadFeed)
</script>

<template>
  <main class="news-page">
    <section class="news-hero">
      <div class="news-hero__eyebrow">Daily dispatch</div>
      <h1>News wall</h1>
      <p>Публичная лента свежих материалов с картинкой, заголовком, превью и полным текстом по клику.</p>
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
      <article v-for="article in articles" :key="article.id" class="news-card card">
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
          </div>

          <RouterLink class="news-card__title" :to="articlePath(article)">
            <h2>{{ article.title }}</h2>
          </RouterLink>
          <p class="news-card__preview">{{ article.preview_text || article.body_text }}</p>

          <div class="news-card__actions">
            <RouterLink class="news-card__link" :to="articlePath(article)">Читать полностью</RouterLink>
            <a :href="article.canonical_url" target="_blank" rel="noreferrer">Открыть источник</a>
          </div>
        </div>
      </article>
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
