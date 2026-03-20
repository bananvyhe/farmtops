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
    if (response.status === 401) {
      window.dispatchEvent(
        new CustomEvent("farmspot:unauthorized", {
          detail: { path: url, method }
        })
      )
    }
    throw new Error(data.error || (data.errors && data.errors.join(", ")) || "Request failed")
  }
  return data
}

export const api = {
  currentSession: () => request("/api/session"),
  login: (payload) => request("/api/session", { method: "POST", body: JSON.stringify(payload) }),
  register: (payload) => request("/api/registration", { method: "POST", body: JSON.stringify(payload) }),
  logout: () => request("/api/session", { method: "DELETE" }),
  dashboard: () => request("/api/dashboard"),
  createPayment: (payload) => request("/api/payments", { method: "POST", body: JSON.stringify(payload) }),
  getPayment: (id) => request(`/api/payments/${id}`),
  adminUsers: () => request("/api/admin/users"),
  updateAdminUser: (id, payload) => request(`/api/admin/users/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  adminTariffs: () => request("/api/admin/tariffs"),
  createTariff: (payload) => request("/api/admin/tariffs", { method: "POST", body: JSON.stringify(payload) }),
  updateTariff: (id, payload) => request(`/api/admin/tariffs/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteTariff: (id) => request(`/api/admin/tariffs/${id}`, { method: "DELETE" })
}
