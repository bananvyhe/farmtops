<script setup>
import { computed, onMounted, ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { api } from "../api"
import { useNewsUiStore } from "../stores/newsUi"

const route = useRoute()
const router = useRouter()
const article = ref(null)
const loading = ref(false)
const error = ref("")
const newsUi = useNewsUiStore()

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

function syncGameBookmarkInArticle(bookmarked, bookmarksCount) {
  if (!article.value?.game) return

  article.value = {
    ...article.value,
    game: {
      ...article.value.game,
      bookmarked,
      ...(typeof bookmarksCount === "number" ? { bookmarks_count: bookmarksCount } : {})
    }
  }

  newsUi.updateGameBookmark(article.value.game.id, bookmarked, bookmarksCount)
}

function gameToggleLabel(game) {
  if (!game) return ""
  return `${game.name} · ${game.bookmarked ? "Выкл" : "Вкл"}`
}

async function toggleGameBookmark() {
  if (!article.value?.game) return

  const nextBookmarked = !article.value.game.bookmarked

  try {
    const data = nextBookmarked
      ? await api.bookmarkNewsGame(article.value.id)
      : await api.unbookmarkNewsGame(article.value.id)

    const bookmarked = Boolean(data.game?.bookmarked ?? nextBookmarked)
    syncGameBookmarkInArticle(bookmarked, data.game?.bookmarks_count)
  } catch (err) {
    error.value = err.message
  }
}

async function loadArticle() {
  loading.value = true
  error.value = ""

  try {
    const data = await api.newsArticle(route.params.id)
    article.value = data.article

    if (data.article?.id) {
      api.markNewsReads({ article_ids: [data.article.id] }).catch(() => {})
    }
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}

watch(() => route.params.id, loadArticle, { immediate: true })

function closeArticle() {
  const backPath = window.history.state?.back
  if (typeof backPath === "string" && backPath.includes("/news")) {
    router.back()
    return
  }

  router.push({ path: "/news", query: route.query })
}

onMounted(() => {
  window.scrollTo({ top: 0, behavior: "auto" })
})
</script>

<template>
  <main class="news-article-page">
    <section class="news-article-shell card">
      <div v-if="loading">
        <v-skeleton-loader type="article, image, paragraph" />
      </div>

      <div v-else-if="article">
        <button type="button" class="news-article-back" @click="closeArticle">← Назад к ленте</button>

        <div class="news-article-meta">
          <v-chip
            v-if="article.game"
            size="small"
            :variant="article.game.bookmarked ? 'flat' : 'outlined'"
            :color="article.game.bookmarked ? 'primary' : undefined"
            class="news-article-game"
            @click.stop="toggleGameBookmark"
          >
            {{ gameToggleLabel(article.game) }}
          </v-chip>
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
          <v-btn color="primary" variant="flat" class="news-article-close" @click="closeArticle">Закрыть</v-btn>
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
  padding: clamp(20px, 3vw, 36px);
  background: rgba(14, 14, 14, 0.96);
  color: #e7e5e5;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.news-article-back {
  display: inline-flex;
  margin-bottom: 16px;
  color: #93cdfc;
  text-decoration: none;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  font-size: 0.82rem;
  background: transparent;
  border: 0;
  padding: 0;
  cursor: pointer;
}

.news-article-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 12px;
  color: #9c9ea0;
  margin-bottom: 16px;
  align-items: center;
  font-size: 0.92rem;
  line-height: 1.35;
}

.news-article-game {
  cursor: pointer;
}

.news-article-title {
  margin: 0 0 18px;
  max-width: none;
  font-size: clamp(2rem, 4vw, 3.15rem);
  line-height: 1.02;
  letter-spacing: -0.045em;
 
}


.news-article-image {
  display: block;
  width: 100%;
  max-height: 520px;
  object-fit: cover;
  margin: 4px 0 8px;
  border-radius: 20px;
}

.news-article-content {
  max-width: 72ch;
  margin-inline: auto;
  padding-top: 2px;
  color: #e7e5e5;
  line-height: 1.88;
  font-size: clamp(1.02rem, 0.22vw + 1rem, 1.1rem);
  overflow-wrap: anywhere;
  text-wrap: pretty;
  hyphens: auto;
}

.news-article-content :deep(p) {
  margin: 0 0 1.05rem;
  line-height: 1.22;
}
.news-article-content :deep(h1) {
  margin: 0 0 18px;
  max-width: none;
  font-size: clamp(2rem, 4vw, 2.15rem);
  line-height: 1.02;
  letter-spacing: -0.045em;
  color: transparent;
  background-image: linear-gradient(
    180deg,
    #f2f0ed 0 50%,
    #c9d7e6 50% 100%
  );
  background-size: 100% 1.02em;
  background-repeat: repeat-y;
  -webkit-background-clip: text;
  background-clip: text;
}
.news-article-content :deep(h2),
.news-article-content :deep(h3),
.news-article-content :deep(h4) {
  margin: 1.7rem 0 0.75rem;
  line-height: 1.18;
  color: #fff;
  text-wrap: balance;
}

.news-article-content :deep(ul),
.news-article-content :deep(ol) {
  margin: 0 0 1.1rem;
  padding-left: 1.45rem;
  display: block;
}

.news-article-content :deep(li) {
  margin: 0 0 0.75rem;
  padding-left: 0.15rem;
  overflow-wrap: anywhere;
  line-height: 1.7;
}

.news-article-content :deep(li::marker) {
  color: #93cdfc;
}

.news-article-content :deep(li > p) {
  margin: 0 0 0.7rem;
}

.news-article-content :deep(li > p:last-child) {
  margin-bottom: 0;
}

.news-article-content :deep(li img),
.news-article-content :deep(li figure),
.news-article-content :deep(li pre),
.news-article-content :deep(li table),
.news-article-content :deep(li blockquote),
.news-article-content :deep(li iframe),
.news-article-content :deep(li video) {
  display: block;
  width: 100%;
  margin: 0.8rem 0 0;
  float: none !important;
}

.news-article-content :deep(li img) {
  max-width: 100%;
  height: auto;
  object-fit: contain;
}

.news-article-content :deep(li figure) {
  margin-inline: 0;
}

.news-article-content :deep(li figure img) {
  margin-top: 0;
}

.news-article-content :deep(li a img) {
  display: block;
  width: 100%;
  margin: 0.8rem 0 0;
}

.news-article-content :deep(blockquote) {
  margin: 1.35rem 0;
  padding: 1.05rem 1.15rem;
  border-left: 3px solid #93cdfc;
  background: rgba(255, 255, 255, 0.04);
  border-radius: 0 16px 16px 0;
  color: #f0eeee;
  line-height: 1.72;
}

.news-article-content :deep(img),
.news-article-content :deep(video),
.news-article-content :deep(iframe) {
  max-width: 100%;
  height: auto;
  margin: 1.15rem 0;
}

.news-article-content :deep(iframe) {
  width: 100%;
  aspect-ratio: 16 / 9;
  border: 0;
}

.news-article-content :deep(table) {
  display: block;
  width: 100%;
  overflow-x: auto;
  border-collapse: collapse;
  margin: 1.2rem 0;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.02);
}

.news-article-content :deep(th),
.news-article-content :deep(td) {
  padding: 0.85rem 0.95rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  line-height: 1.45;
}

.news-article-content :deep(pre) {
  overflow-x: auto;
  padding: 1.05rem 1.1rem;
  margin: 1.1rem 0;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.06);
  line-height: 1.65;
}

.news-article-content :deep(code) {
  padding: 0.15rem 0.35rem;
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.08);
}

.news-article-content :deep(a) {
  color: #93cdfc;
}

.news-article-content :deep(.w4pl) {
  display: grid;
  gap: 1rem;
  margin: 1.25rem 0;
  padding: 1rem;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.news-article-content :deep(.w4pl-inner) {
  display: block;
}

.news-article-content :deep(.roundupimg) {
  display: block;
  width: 75px;
  height: 75px;
  margin: 0 0 0.65rem;
  overflow: hidden;
  border-radius: 14px;
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.news-article-content :deep(.roundupimg img) {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
  margin: 0;
}

.news-article-content :deep(.rounduplink) {
  display: block;
  min-width: 0;
  line-height: 1.35;
  margin: 0 0 0.35rem;
}

.news-article-content :deep(.rounduplink a) {
  font-weight: 700;
  color: #fff;
  text-decoration: none;
}

.news-article-content :deep(.w4pl br) {
  display: none;
}

.news-article-content :deep(.w4pl > p),
.news-article-content :deep(.w4pl > span),
.news-article-content :deep(.w4pl > a) {
  display: block;
}

.news-article-links {
  max-width: 72ch;
  margin: 22px auto 0;
  display: flex;
  align-items: center;
  gap: 16px 18px;
  flex-wrap: wrap;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
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
