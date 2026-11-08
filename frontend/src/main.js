import { createApp } from "vue"
import { createRouter, createWebHistory } from "vue-router"
import App from "./App.vue"
import { createPinia } from "pinia"
import vuetify from "./plugins/vuetify"
import { setSeo } from "./seo"
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
  {
    path: "/login",
    component: () => import("./pages/LoginPage.vue"),
    meta: {
      title: "Вход",
      description: "Войдите в Farmspot, чтобы открыть личный кабинет и дополнительные функции.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/news",
    component: () => import("./pages/NewsPage.vue"),
    meta: {
      title: "Новости",
      description: "Свежие новости Farmspot и связанные игровые материалы."
    }
  },
  {
    path: "/news/:id",
    component: () => import("./pages/NewsArticlePage.vue"),
    meta: {
      title: "Новость",
      description: "Открыть полную версию новости Farmspot."
    }
  },
  {
    path: "/profile",
    component: () => import("./pages/ProfilePage.vue"),
    meta: {
      title: "Профиль",
      description: "Личный профиль пользователя Farmspot.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/world/:id",
    component: () => import("./pages/ShardWorldPage.vue"),
    meta: {
      title: "Мир",
      description: "Публичная страница мира Farmspot.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/dashboard",
    component: () => import("./pages/DashboardPage.vue"),
    meta: {
      title: "Кабинет",
      description: "Панель управления балансом и платежами Farmspot.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/admin",
    component: () => import("./pages/AdminPage.vue"),
    meta: {
      title: "Админка",
      description: "Административная панель Farmspot.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/404",
    component: () => import("./pages/NotFoundPage.vue"),
    meta: {
      title: "Страница не найдена",
      description: "Запрошенная страница Farmspot не найдена.",
      robots: "noindex, nofollow"
    }
  },
  {
    path: "/:pathMatch(.*)*",
    redirect: "/404"
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior() {
    return { top: 0 }
  }
})
const pinia = createPinia()

function updateSeoForRoute(route) {
  setSeo({
    title: route.meta.title,
    description: route.meta.description,
    robots: route.meta.robots,
    canonicalPath: route.path
  })
}

router.afterEach((to) => {
  updateSeoForRoute(to)
})

if (typeof window !== "undefined" && "scrollRestoration" in window.history) {
  window.history.scrollRestoration = "manual"
}

router.isReady().then(() => {
  updateSeoForRoute(router.currentRoute.value)
})

createApp(App).use(pinia).use(router).use(vuetify).mount("#app")
