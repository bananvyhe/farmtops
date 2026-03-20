<script setup>
import { onMounted, ref } from "vue"
import { api } from "../api"
import { sessionState } from "../useSession"

const data = ref(null)
const error = ref("")
const amountRubles = ref("")
const payment = ref(null)

const formatCurrency = (cents) =>
  new Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB" }).format((cents || 0) / 100)

async function loadDashboard() {
  try {
    data.value = await api.dashboard()
  } catch (err) {
    error.value = err.message
  }
}

async function createPayment(method) {
  error.value = ""
  try {
    payment.value = await api.createPayment({ amount_rubles: amountRubles.value, payment_method: method })
  } catch (err) {
    error.value = err.message
  }
}

function submitExternal(fields) {
  const form = document.createElement("form")
  form.method = "POST"
  form.action = payment.value.form.endpoint
  Object.entries(fields).forEach(([key, value]) => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = key
    input.value = value
    form.appendChild(input)
  })
  document.body.appendChild(form)
  form.submit()
}

onMounted(loadDashboard)
</script>

<template>
  <main class="page-grid" v-if="sessionState.user && data">
    <section class="stats">
      <article class="metric card">
        <span>Баланс</span>
        <strong>{{ formatCurrency(data.user.balance_cents) }}</strong>
      </article>
      <article class="metric card">
        <span>Списание в час</span>
        <strong>{{ formatCurrency(data.user.hourly_rate_cents) }}</strong>
      </article>
      <article class="metric card">
        <span>Осталось дней</span>
        <strong>{{ data.user.remaining_days ?? "∞" }}</strong>
      </article>
    </section>

    <section class="card">
      <h2>Аккаунт</h2>
      <div class="detail-list">
        <div><span>E-mail</span><strong>{{ data.user.email }}</strong></div>
        <div><span>Роль</span><strong>{{ data.user.role }}</strong></div>
        <div><span>Тариф</span><strong>{{ data.user.tariff_name }}</strong></div>
      </div>
    </section>

    <section class="card">
      <h2>Пополнить баланс</h2>
      <p class="muted">Списание происходит равными долями каждый час</p>
      <div class="pay-box">
        <input v-model="amountRubles" type="number" min="1" step="0.01" placeholder="Сумма в рублях" />
        <div class="button-row">
          <button @click="createPayment('bank_card')">Создать оплату картой</button>
          <button class="ghost" @click="createPayment('wallet')">Создать оплату кошельком</button>
        </div>
      </div>
      <div v-if="payment" class="payment-result">
        <p>Платёж создан: {{ payment.payment.label }}</p>
        <p v-if="!payment.form.configured" class="muted">YooMoney реквизиты ещё не заполнены.</p>
        <div v-else class="button-row">
          <button @click="submitExternal(payment.form.card_fields)">Оплатить картой</button>
          <button class="ghost" @click="submitExternal(payment.form.wallet_fields)">Оплатить кошельком</button>
        </div>
      </div>
    </section>

    <section class="card">
      <h2>Последние платежи</h2>
      <table>
        <thead><tr><th>ID</th><th>Сумма</th><th>Статус</th></tr></thead>
        <tbody>
          <tr v-for="item in data.recent_payments" :key="item.id">
            <td>{{ item.label }}</td>
            <td>{{ formatCurrency(item.requested_amount_cents) }}</td>
            <td>{{ item.status }}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <section class="card">
      <h2>Движение средств</h2>
      <table>
        <thead><tr><th>Дата</th><th>Тип</th><th>Сумма</th><th>Баланс после</th></tr></thead>
        <tbody>
          <tr v-for="item in data.recent_entries" :key="item.id">
            <td>{{ new Date(item.created_at).toLocaleString("ru-RU") }}</td>
            <td>{{ item.kind }}</td>
            <td>{{ formatCurrency(item.amount_cents) }}</td>
            <td>{{ formatCurrency(item.balance_after_cents) }}</td>
          </tr>
        </tbody>
      </table>
    </section>
    <p v-if="error" class="error">{{ error }}</p>
  </main>
</template>
