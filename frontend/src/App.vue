<script setup>
import { computed, onMounted, onUnmounted, shallowRef, watch } from "vue"
import { useRouter } from "vue-router"
import { clearSession, loadSession, logout, sessionState } from "./useSession"
import { useNewsUiStore } from "./stores/newsUi"

const Hat = shallowRef(null)
const desktopViewport = window.matchMedia("(min-width: 768px)")

const router = useRouter()
const newsUi = useNewsUiStore()
const publicPaths = new Set(["/login", "/news", "/404"])
const currentPath = computed(() => router.currentRoute.value.path)
const isPublicNewsRoute = computed(() => currentPath.value === "/news" || currentPath.value.startsWith("/news/"))

async function handleUnauthorized() {
  clearSession()
  newsUi.clearFeedSnapshot()
  if (!publicPaths.has(currentPath.value)) {
    await router.replace("/login")
  }
}

watch(
  () => sessionState.authenticated,
  (nextValue, prevValue) => {
    if (nextValue === prevValue) return

    newsUi.clearFeedSnapshot()
    window.dispatchEvent(
      new CustomEvent("farmspot:session-changed", {
        detail: { authenticated: nextValue }
      })
    )
  }
)

onMounted(async () => {
  window.addEventListener("farmspot:unauthorized", handleUnauthorized)

  // Do not download the animation component and its assets on mobile.
  if (desktopViewport.matches) {
    import("./components/Hat.vue").then((module) => { Hat.value = module.default })
  }

  try {
    await loadSession()
    if (sessionState.authenticated && currentPath.value === "/login") {
      router.replace(sessionState.user?.role === "admin" ? "/admin" : "/profile")
    }
    if (!sessionState.authenticated && !publicPaths.has(currentPath.value) && !isPublicNewsRoute.value) {
      router.replace("/news")
    }
  } catch {
    if (!publicPaths.has(currentPath.value) && !isPublicNewsRoute.value) {
      router.replace("/news")
    }
  }
})

onUnmounted(() => {
  window.removeEventListener("farmspot:unauthorized", handleUnauthorized)
})

async function handleLogout() {
  await logout()
  router.replace("/news")
}
</script>

<template>
  <div class="app-shell">
     
    <component :is="Hat" v-if="Hat" />
    <div v-else class="hat-placeholder" aria-hidden="true"></div>
    <header class="app-topbar">
      <div class="app-brand">
        <div class="eyebrow">farmspot.ru</div>
      </div>
      <nav class="nav"> 
        <RouterLink to="/news" class="ghost">Новости</RouterLink>
        <RouterLink v-if="!sessionState.authenticated" to="/login" class="ghost">Войти</RouterLink>
        <RouterLink v-if="sessionState.authenticated" to="/profile" class="ghost">Профиль</RouterLink>
        <RouterLink v-if="sessionState.authenticated && sessionState.user?.role === 'admin'" to="/admin" class="ghost">Админка</RouterLink>
        <button v-if="sessionState.authenticated" class="danger" @click="handleLogout">Выйти</button>
      </nav>
    </header>
    <RouterView />
  </div>
</template>
