<script setup>
import { computed, onMounted, onUnmounted } from "vue"
import { useRouter } from "vue-router"
import { clearSession, loadSession, logout, sessionState } from "./useSession"

const router = useRouter()
const publicPaths = new Set(["/login", "/news"])
const currentPath = computed(() => router.currentRoute.value.path)
const isPublicNewsRoute = computed(() => currentPath.value === "/news" || currentPath.value.startsWith("/news/"))

async function handleUnauthorized() {
  clearSession()
  if (!publicPaths.has(currentPath.value)) {
    await router.replace("/login")
  }
}

onMounted(async () => {
  window.addEventListener("farmspot:unauthorized", handleUnauthorized)

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
    <header class="app-topbar  ">
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
