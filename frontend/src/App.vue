<script setup>
import { onMounted, onUnmounted } from "vue"
import { useRouter } from "vue-router"
import { clearSession, loadSession, logout, sessionState } from "./useSession"

const router = useRouter()

async function handleUnauthorized() {
  clearSession()
  if (router.currentRoute.value.path !== "/login") {
    await router.replace("/login")
  }
}

onMounted(async () => {
  window.addEventListener("farmspot:unauthorized", handleUnauthorized)

  try {
    await loadSession()
    if (sessionState.authenticated && router.currentRoute.value.path === "/login") {
      router.replace(sessionState.user?.role === "admin" ? "/admin" : "/dashboard")
    }
    if (!sessionState.authenticated && router.currentRoute.value.path !== "/login") {
      router.replace("/login")
    }
  } catch {
    if (router.currentRoute.value.path !== "/login") {
      router.replace("/login")
    }
  }
})

onUnmounted(() => {
  window.removeEventListener("farmspot:unauthorized", handleUnauthorized)
})

async function handleLogout() {
  await logout()
  router.replace("/login")
}
</script>

<template>
  <div class="app-shell">
    <header class="topbar">
      <div>
        <div class="eyebrow">farmspot.ru</div>
        <!-- <h1>ммо /h1> -->
      </div>
      <nav class="nav" v-if="sessionState.authenticated">
        <RouterLink to="/dashboard" class="ghost">Кабинет</RouterLink>
        <RouterLink v-if="sessionState.user?.role === 'admin'" to="/admin" class="ghost">Админка</RouterLink>
        <button class="danger" @click="handleLogout">Выйти</button>
      </nav>
    </header>
    <RouterView />
  </div>
</template>
