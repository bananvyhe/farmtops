import { reactive } from "vue"
import { api } from "./api"

export const sessionState = reactive({
  ready: false,
  authenticated: false,
  user: null
})

export function clearSession() {
  sessionState.ready = true
  sessionState.authenticated = false
  sessionState.user = null
}

export async function loadSession() {
  try {
    const data = await api.currentSession()
    sessionState.ready = true
    sessionState.authenticated = data.authenticated
    sessionState.user = data.user || null
    return data
  } catch (error) {
    clearSession()
    throw error
  }
}

export async function login(credentials) {
  const data = await api.login(credentials)
  sessionState.authenticated = true
  sessionState.user = data.user
  return data
}

export async function register(credentials) {
  const data = await api.register(credentials)
  sessionState.authenticated = true
  sessionState.user = data.user
  return data
}

export async function logout() {
  await api.logout()
  clearSession()
}
