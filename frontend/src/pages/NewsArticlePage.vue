<script setup>
import { computed, ref, watch } from "vue"
import { useRoute } from "vue-router"
import { api } from "../api"

const route = useRoute()
const article = ref(null)
const loading = ref(false)
const error = ref("")

const formatDate = (value) => {
  if (!value) return "—"
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(new Date(value))
}

const escapeHtml = (value) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")

const bodyHtml = computed(() => {
  if (!article.value) return ""

  const richHtml = article.value.body_html || ""
  const plainText = article.value.body_text || ""
  const richHtmlLooksComplete = richHtml && richHtml.length >= Math.max(400, plainText.length)

  if (richHtmlLooksComplete) return richHtml
  if (plainText) {
    return plainText
      .split(/\n{2,}/)
      .map((paragraph) => `<p>${escapeHtml(paragraph).replace(/\n/g, "<br>")}</p>`)
      .join("")
  }
  return richHtml
})

async function loadArticle() {
  loading.value = true
  error.value = ""

  try {
    const data = await api.newsArticle(route.params.id)
    article.value = data.article
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}

watch(() => route.params.id, loadArticle, { immediate: true })
</script>

<template>
  <main class="news-article-page">
    <section class="news-article-shell card">
      <div v-if="loading">
        <v-skeleton-loader type="article, image, paragraph" />
      </div>

      <div v-else-if="article">
        <RouterLink to="/news" class="news-article-back">← Назад к ленте</RouterLink>

        <div class="news-article-meta">
          <span>{{ article.source_name }}</span>
          <span>{{ article.section_name }}</span>
          <span>{{ formatDate(article.published_at || article.fetched_at) }}</span>
        </div>

        <h1 class="news-article-title">{{ article.title }}</h1>

        <img
          v-if="article.image_url"
          :src="article.image_url"
          :alt="article.title"
          class="news-article-image"
        >

        <div class="news-article-content" v-html="bodyHtml" />

        <div class="news-article-links">
          <a :href="article.canonical_url" target="_blank" rel="noreferrer">Открыть оригинал</a>
          <v-btn to="/news" color="primary" variant="flat" class="news-article-close">Закрыть</v-btn>
        </div>
      </div>

      <div v-else class="news-article-empty">
        <h2>Новость не найдена</h2>
        <p v-if="error">{{ error }}</p>
      </div>
    </section>
  </main>
</template>

<style scoped>
.news-article-page {
  min-height: calc(100vh - 120px);
  margin-top: 8px;
  padding-bottom: 40px;
}

.news-article-shell {
  padding: 22px;
  background: rgba(14, 14, 14, 0.96);
  color: #e7e5e5;
}

.news-article-back {
  display: inline-flex;
  margin-bottom: 16px;
  color: #93cdfc;
  text-decoration: none;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  font-size: 0.82rem;
}

.news-article-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  color: #9c9ea0;
  margin-bottom: 14px;
}

.news-article-title {
  margin: 0 0 18px;
  font-size: clamp(1.8rem, 4vw, 3rem);
  line-height: 1.05;
  letter-spacing: -0.04em;
}

.news-article-image {
  width: 100%;
  max-height: 520px;
  object-fit: cover;
  margin-bottom: 18px;
}

.news-article-content {
  color: #e7e5e5;
  line-height: 1.75;
}

.news-article-content :deep(p) {
  margin: 0 0 1rem;
}

.news-article-content :deep(img),
.news-article-content :deep(video),
.news-article-content :deep(iframe) {
  max-width: 100%;
  height: auto;
  margin: 1rem 0;
}

.news-article-content :deep(iframe) {
  width: 100%;
  aspect-ratio: 16 / 9;
  border: 0;
}

.news-article-content :deep(a) {
  color: #93cdfc;
}

.news-article-links {
  margin-top: 22px;
  display: flex;
  align-items: center;
  gap: 18px;
  flex-wrap: wrap;
}

.news-article-links a {
  color: #93cdfc;
  text-decoration: none;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  font-size: 0.82rem;
}

.news-article-empty {
  color: #e7e5e5;
}
</style>
