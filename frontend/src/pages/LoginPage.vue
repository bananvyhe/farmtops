<script setup>
import { computed, reactive, ref } from "vue"
import { useRouter } from "vue-router"
import { login, register } from "../useSession"

const router = useRouter()
const mode = ref("login")
const form = reactive({
  email: "",
  password: "",
  passwordConfirmation: ""
})
const error = ref("")
const loading = ref(false)
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

const isEmailValid = computed(() => emailPattern.test(form.email.trim()))
const isPasswordLongEnough = computed(() => form.password.length >= 8)
const doPasswordsMatch = computed(() => form.password.length > 0 && form.password === form.passwordConfirmation)
const canLogin = computed(() => isEmailValid.value && form.password.length > 0)
const canRegister = computed(() => isEmailValid.value && isPasswordLongEnough.value && doPasswordsMatch.value)

async function submit() {
  error.value = ""

  if (mode.value === "login" && !canLogin.value) {
    error.value = "Проверьте e-mail и пароль."
    return
  }

  if (mode.value === "register" && !canRegister.value) {
    error.value = "Исправьте поля регистрации."
    return
  }

  loading.value = true

  try {
    const data = mode.value === "login"
      ? await login({ email: form.email.trim(), password: form.password })
      : await register({
          email: form.email.trim(),
          password: form.password,
          password_confirmation: form.passwordConfirmation
        })

    router.replace(data.user.role === "admin" ? "/admin" : "/profile")
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="hero">
    <section class="card intro">
      <div class="eyebrow">сохраните ваш прогресс</div>

      <p>
        регистрация необходима для сохранения аккаунта и доступа к дополнительным функциям
      </p>
    </section>

    <section class="card form-card">
      <h2>{{ mode === "login" ? "Войти" : "Создать аккаунт" }}</h2>
      <v-tabs v-model="mode" color="primary" grow class="auth-tabs">
        <v-tab value="login">Вход</v-tab>
        <v-tab value="register">Регистрация</v-tab>
      </v-tabs>

      <p v-if="error" class="error">{{ error }}</p>

      <form novalidate @submit.prevent="submit">
        <label>
          E-mail
          <input v-model="form.email" type="text" inputmode="email" autocomplete="email" />
          <span :class="isEmailValid || !form.email ? 'hint' : 'error'">
            {{ !form.email ? "Введите e-mail" : isEmailValid ? "E-mail выглядит корректно" : "Некорректный формат e-mail" }}
          </span>
        </label>

        <label>
          Пароль
          <input v-model="form.password" type="password" autocomplete="current-password" />
          <span :class="isPasswordLongEnough || !form.password ? 'hint' : 'error'">
            {{ !form.password ? "Введите пароль" : isPasswordLongEnough ? "Минимальная длина соблюдена" : "Пароль должен быть не короче 8 символов" }}
          </span>
        </label>
        <label v-if="mode === 'register'">
          Повторите пароль
          <input v-model="form.passwordConfirmation" type="password" autocomplete="new-password" />
          <span :class="doPasswordsMatch || !form.passwordConfirmation ? 'hint' : 'error'">
            {{
              !form.passwordConfirmation
                ? "Повторите пароль"
                : doPasswordsMatch
                  ? "Пароли совпадают"
                  : "Пароли не совпадают"
            }}
          </span>
        </label>
        <v-btn
          :disabled="loading || (mode === 'login' ? !canLogin : !canRegister)"
          color="primary"
          rounded="xl"
          size="large"
          block
          type="submit"
        >
          {{
            loading
              ? mode === "login" ? "Входим..." : "Регистрируем..."
              : mode === "login" ? "Войти" : "Зарегистрироваться"
          }}
        </v-btn>
      </form>
    </section>
  </main>
</template>
