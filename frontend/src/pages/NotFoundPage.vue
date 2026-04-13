<script setup>
import { onMounted } from "vue"
import { setSeo } from "../seo"

onMounted(() => {
  setSeo({
    title: "Страница не найдена",
    description: "Запрошенная страница Farmspot не найдена.",
    canonicalPath: "/404",
    robots: "noindex, nofollow"
  })
})
</script>

<template>
  <main class="hero">
    <section class="card intro">
      <div class="eyebrow">404</div>
      <h1>Страница не найдена</h1>
      <p>Проверьте адрес или вернитесь в ленту новостей.</p>
      <RouterLink to="/news" class="ghost">Перейти к новостям</RouterLink>
    </section>
  </main>
</template>
