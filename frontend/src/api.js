const jsonHeaders = {
  "Content-Type": "application/json",
  Accept: "application/json"
}

let csrfToken = null

export function setCsrfToken(token) {
  csrfToken = token
}

async function request(url, options = {}) {
  const headers = { ...jsonHeaders, ...(options.headers || {}) }
  const method = (options.method || "GET").toUpperCase()
  if (csrfToken && !["GET", "HEAD"].includes(method)) {
    headers["X-CSRF-Token"] = csrfToken
  }

  const response = await fetch(url, {
    ...options,
    headers
  })

  const data = await response.json().catch(() => ({}))
  if (data.csrf_token) setCsrfToken(data.csrf_token)
  if (!response.ok) {
    const error = new Error(data.error || (data.errors && data.errors.join(", ")) || "Request failed")
    error.status = response.status
    if (response.status === 401) {
      window.dispatchEvent(
        new CustomEvent("farmspot:unauthorized", {
          detail: { path: url, method }
        })
      )
    }
    throw error
  }
  return data
}

function withQuery(path, params = {}) {
  const search = new URLSearchParams()
  Object.entries(params).forEach(([key, value]) => {
    if (value === null || value === undefined || value === "") return
    search.set(key, value)
  })
  const query = search.toString()
  return query ? `${path}?${query}` : path
}

export const api = {
  currentSession: () => request("/api/session"),
  login: (payload) => request("/api/session", { method: "POST", body: JSON.stringify(payload) }),
  register: (payload) => request("/api/registration", { method: "POST", body: JSON.stringify(payload) }),
  logout: () => request("/api/session", { method: "DELETE" }),
  profile: () => request("/api/profile"),
  updateProfile: (payload) => request("/api/profile", { method: "PATCH", body: JSON.stringify(payload) }),
  checkProfileNickname: (nickname) => request(withQuery("/api/profile/nickname_check", { nickname })),
  shards: () => request("/api/shards"),
  shardWorld: (id) => request(`/api/shards/${id}/world`),
  enterShard: (id, layerId = null) =>
    request(withQuery(`/api/shards/${id}/enter`, { layer_id: layerId }), { method: "POST" }),
  leaveShard: (id) => request(`/api/shards/${id}/leave`, { method: "DELETE" }),
  createShard: (gameId) => request(`/api/games/${gameId}/shard`, { method: "POST" }),
  dashboard: () => request("/api/dashboard"),
  createPayment: (payload) => request("/api/payments", { method: "POST", body: JSON.stringify(payload) }),
  getPayment: (id) => request(`/api/payments/${id}`),
  adminUsers: () => request("/api/admin/users"),
  updateAdminUser: (id, payload) => request(`/api/admin/users/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteAdminUser: (id) => request(`/api/admin/users/${id}`, { method: "DELETE" }),
  adminTariffs: () => request("/api/admin/tariffs"),
  createTariff: (payload) => request("/api/admin/tariffs", { method: "POST", body: JSON.stringify(payload) }),
  updateTariff: (id, payload) => request(`/api/admin/tariffs/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteTariff: (id) => request(`/api/admin/tariffs/${id}`, { method: "DELETE" }),
  news: (params = {}) => request(withQuery("/api/news", params)),
  newsArticle: (id) => request(`/api/news/${id}`),
  markNewsReads: (payload) => request("/api/news/reads", { method: "POST", body: JSON.stringify(payload) }),
  bookmarkNewsGame: (articleId) => request(`/api/news/${articleId}/bookmark_game`, { method: "POST" }),
  unbookmarkNewsGame: (articleId) => request(`/api/news/${articleId}/unbookmark_game`, { method: "DELETE" }),
  adminNewsSources: () => request("/api/admin/news_sources"),
  createNewsSource: (payload) => request("/api/admin/news_sources", { method: "POST", body: JSON.stringify(payload) }),
  updateNewsSource: (id, payload) => request(`/api/admin/news_sources/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteNewsSource: (id) => request(`/api/admin/news_sources/${id}`, { method: "DELETE" }),
  crawlNewsSource: (id) => request(`/api/admin/news_sources/${id}/crawl`, { method: "POST" }),
  createNewsSection: (sourceId, payload) =>
    request(`/api/admin/news_sources/${sourceId}/news_sections`, { method: "POST", body: JSON.stringify(payload) }),
  updateNewsSection: (sourceId, id, payload) =>
    request(`/api/admin/news_sources/${sourceId}/news_sections/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteNewsSection: (sourceId, id) =>
    request(`/api/admin/news_sources/${sourceId}/news_sections/${id}`, { method: "DELETE" })
}
