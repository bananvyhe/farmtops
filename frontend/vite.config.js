import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"
import vuetify from "vite-plugin-vuetify"

export default defineConfig({
  plugins: [
    vue(),
    vuetify({ autoImport: true })
  ],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:3000",
      "/cable": {
        target: "ws://127.0.0.1:3000",
        ws: true,
        changeOrigin: true
      },
      "/robots.txt": {
        target: "http://127.0.0.1:3000",
        changeOrigin: true
      },
      "/sitemap.xml": {
        target: "http://127.0.0.1:3000",
        changeOrigin: true
      },
      "/admin": {
        target: "http://127.0.0.1:3000",
        changeOrigin: true
      },
      "/sidekiq": {
        target: "http://127.0.0.1:3000",
        changeOrigin: true
      },
      "/up": {
        target: "http://127.0.0.1:3000",
        changeOrigin: true
      }
    }
  }
})
