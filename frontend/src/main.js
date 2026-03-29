import { createApp } from "vue"
import { createRouter, createWebHistory } from "vue-router"
import App from "./App.vue"
import LoginPage from "./pages/LoginPage.vue"
import DashboardPage from "./pages/DashboardPage.vue"
import AdminPage from "./pages/AdminPage.vue"
import NewsPage from "./pages/NewsPage.vue"
import NewsArticlePage from "./pages/NewsArticlePage.vue"
import { createPinia } from "pinia"
import vuetify from "./plugins/vuetify"
import "./styles.css"

if (import.meta.env.PROD) {
  const gaId = "G-QC89HYMM4R"
  const gtagScript = document.createElement("script")
  gtagScript.async = true
  gtagScript.src = `https://www.googletagmanager.com/gtag/js?id=${gaId}`
  document.head.appendChild(gtagScript)

  window.dataLayer = window.dataLayer || []
  function gtag() {
    window.dataLayer.push(arguments)
  }
  gtag("js", new Date())
  gtag("config", gaId)
}

const routes = [
  { path: "/", redirect: "/news" },
  { path: "/login", component: LoginPage },
  { path: "/news", component: NewsPage },
  { path: "/news/:id", component: NewsArticlePage },
  { path: "/dashboard", component: DashboardPage },
  { path: "/admin", component: AdminPage }
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior() {
    return { top: 0 }
  }
})
const pinia = createPinia()

if (typeof window !== "undefined" && "scrollRestoration" in window.history) {
  window.history.scrollRestoration = "manual"
}

createApp(App).use(pinia).use(router).use(vuetify).mount("#app")
