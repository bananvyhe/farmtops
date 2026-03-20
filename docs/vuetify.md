# Vuetify и UI-правила

## Подключение

- Плагин: `/Users/rufus/workspace/projects/farmspot/frontend/src/plugins/vuetify.js`
- Инициализация: `/Users/rufus/workspace/projects/farmspot/frontend/src/main.js`

## Тема и переменные

- Основные CSS-переменные проекта лежат в:
  `/Users/rufus/workspace/projects/farmspot/frontend/src/styles.css`
- Цвета темы Vuetify синхронизированы с этими переменными в `farmspotTheme`.

## Таб-переключатели

На экранах авторизации используем `v-tabs`. Активный таб должен быть явно подсвечен.

- Компонент: `LoginPage.vue`
- Стили: `.auth-tabs` в `/Users/rufus/workspace/projects/farmspot/frontend/src/styles.css`

## Кнопки удаления

Кнопки «удалить» — только иконка (круглая), без текста.

Пример:

```vue
<v-btn
  icon="mdi-delete"
  variant="tonal"
  color="error"
  size="small"
  aria-label="Удалить"
  title="Удалить"
/>
```
