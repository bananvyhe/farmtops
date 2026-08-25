import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"
import vuetify from "vite-plugin-vuetify"

const apiProxyTarget = process.env.VITE_API_PROXY_TARGET || "http://127.0.0.1:3000"
const cableProxyTarget = apiProxyTarget.replace(/^http/, "ws")

export default defineConfig({
  plugins: [
    vue(),
    vuetify({ autoImport: true })
  ],
  server: {
    host: "127.0.0.1",
    port: 5173,
    allowedHosts: ["localhost", "127.0.0.1"],
    proxy: {
      "/api": apiProxyTarget,
      "/cable": {
        target: cableProxyTarget,
        ws: true,
        changeOrigin: true
      },
      "/robots.txt": {
        target: apiProxyTarget,
        changeOrigin: true
      },
      "/sitemap.xml": {
        target: apiProxyTarget,
        changeOrigin: true
      },
      "/admin": {
        target: apiProxyTarget,
        changeOrigin: true
      },
      "/sidekiq": {
        target: apiProxyTarget,
        changeOrigin: true
      },
      "/up": {
        target: apiProxyTarget,
        changeOrigin: true
      }
    }
  }
})
