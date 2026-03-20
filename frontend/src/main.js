import { createApp } from "vue"
import { createRouter, createWebHistory } from "vue-router"
import App from "./App.vue"
import LoginPage from "./pages/LoginPage.vue"
import DashboardPage from "./pages/DashboardPage.vue"
import AdminPage from "./pages/AdminPage.vue"
import vuetify from "./plugins/vuetify"
import "./styles.css"

if (import.meta.env.PROD) {
  const gaId = "G-PPKP0L3CY7"
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
  { path: "/", redirect: "/login" },
  { path: "/login", component: LoginPage },
  { path: "/dashboard", component: DashboardPage },
  { path: "/admin", component: AdminPage }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

createApp(App).use(router).use(vuetify).mount("#app")
