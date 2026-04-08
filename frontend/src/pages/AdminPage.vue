<script setup>
import { onMounted, reactive, ref } from "vue"
import { api } from "../api"
import { sessionState } from "../useSession"

const users = ref([])
const tariffs = ref([])
const error = ref("")
const tariffForm = reactive({
  name: "",
  monthly_price_rubles: "",
  billing_period_days: 30,
  description: "",
  active: true
})

const formatCurrency = (cents) =>
  new Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB" }).format((cents || 0) / 100)

async function loadAdmin() {
  try {
    const [usersData, tariffsData] = await Promise.all([api.adminUsers(), api.adminTariffs()])
    users.value = usersData.users
    tariffs.value = tariffsData.tariffs
  } catch (err) {
    error.value = err.message
  }
}

async function saveUser(user) {
  try {
    const data = await api.updateAdminUser(user.id, {
      role: user.role,
      tariff_id: user.tariff_id,
      hourly_rate_cents: user.manual_hourly_rate_cents,
      active: user.active
    })
    Object.assign(user, data.user)
  } catch (err) {
    error.value = err.message
  }
}

async function deleteUser(user) {
  if (!window.confirm(`Удалить пользователя ${user.email}? Все его данные будут удалены.`)) return

  try {
    await api.deleteAdminUser(user.id)
    users.value = users.value.filter((candidate) => candidate.id !== user.id)
  } catch (err) {
    error.value = err.message
  }
}

async function createTariff() {
  try {
    await api.createTariff({
      ...tariffForm,
      monthly_price_cents: Math.round(Number(tariffForm.monthly_price_rubles || 0) * 100)
    })
    tariffForm.name = ""
    tariffForm.monthly_price_rubles = ""
    tariffForm.billing_period_days = 30
    tariffForm.description = ""
    tariffForm.active = true
    await loadAdmin()
  } catch (err) {
    error.value = err.message
  }
}

async function deleteTariff(tariff) {
  if (!window.confirm(`Удалить тариф "${tariff.name}"?`)) return

  try {
    await api.deleteTariff(tariff.id)
    await loadAdmin()
  } catch (err) {
    error.value = err.message
  }
}

onMounted(loadAdmin)
</script>

<template>
  <main class="page-grid" v-if="sessionState.user?.role === 'admin'">
    <section class="card">
      <h2>Месячные тарифы</h2>
      <table>
        <thead><tr><th>Название</th><th>Цена в месяц</th><th>Списание в час</th><th>Дней</th><th></th></tr></thead>
        <tbody>
          <tr v-for="tariff in tariffs" :key="tariff.id">
            <td>{{ tariff.name }}</td>
            <td>{{ formatCurrency(tariff.monthly_price_cents) }}</td>
            <td>{{ formatCurrency(tariff.hourly_rate_cents) }}</td>
            <td>{{ tariff.billing_period_days }}</td>
            <td>
              <v-btn
                icon="mdi-delete"
                variant="tonal"
                color="error"
                size="small"
                aria-label="Удалить тариф"
                title="Удалить тариф"
                @click="deleteTariff(tariff)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <section class="card">
      <h2>Новый тариф</h2>
      <div class="form-grid">
        <input v-model="tariffForm.name" placeholder="Название" />
        <input v-model="tariffForm.monthly_price_rubles" type="number" min="0" step="0.01" placeholder="Цена в месяц, руб." />
        <input v-model="tariffForm.billing_period_days" type="number" min="1" step="1" placeholder="Дней" />
        <textarea v-model="tariffForm.description" rows="3" placeholder="Описание"></textarea>
        <label class="checkbox">
          <input v-model="tariffForm.active" type="checkbox" />
          Активен
        </label>
        <button @click="createTariff">Добавить тариф</button>
      </div>
    </section>

    <section class="card card-wide">
      <h2>Пользователи</h2>
      <table>
        <thead><tr><th>E-mail</th><th>Роль</th><th>Тариф</th><th>Ручное списание</th><th>Баланс</th><th>Активен</th><th></th><th></th></tr></thead>
        <tbody>
          <tr v-for="user in users" :key="user.id">
            <td>{{ user.email }}</td>
            <td>
              <select v-model="user.role">
                <option value="admin">admin</option>
                <option value="user">user</option>
                <option value="client">client</option>
              </select>
            </td>
            <td>
              <select v-model="user.tariff_id">
                <option :value="null">Индивидуальный</option>
                <option v-for="tariff in tariffs" :key="tariff.id" :value="tariff.id">{{ tariff.name }}</option>
              </select>
            </td>
            <td><input v-model="user.manual_hourly_rate_cents" type="number" min="0" step="1" /></td>
            <td>{{ formatCurrency(user.balance_cents) }}</td>
            <td><input v-model="user.active" type="checkbox" /></td>
            <td><button @click="saveUser(user)">Сохранить</button></td>
            <td>
              <v-btn
                icon="mdi-delete"
                variant="tonal"
                color="error"
                size="small"
                aria-label="Удалить пользователя"
                title="Удалить пользователя"
                @click="deleteUser(user)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    <p v-if="error" class="error">{{ error }}</p>
  </main>
</template>
