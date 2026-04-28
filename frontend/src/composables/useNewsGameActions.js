import { computed, ref } from "vue"
import { useRouter } from "vue-router"
import { api } from "../api"
import { sessionState } from "../useSession"
import { useNewsUiStore } from "../stores/newsUi"

export function useNewsGameActions(article) {
  const creatingShardGameId = ref(null)
  const error = ref("")
  const router = useRouter()
  const newsUi = useNewsUiStore()

  const _article = (ref) => (ref && typeof ref === "object" && Object.prototype.hasOwnProperty.call(ref, "value") ? ref : ref)

  const getArticle = () => (_article(article)?.value ?? article)

  const shardTooltip = computed(() => {
    const a = getArticle()
    if (!a?.game) return ""
    if (!a.game.can_create_shard) return "У игры пока нет следящих."
    if (!sessionState.authenticated) return "Для входа в мир необходима регистрация."
    return "Создать шард этой игры."
  })

  const canEnterWorld = computed(() => {
    const a = getArticle()
    return Boolean(a?.game?.can_create_shard && sessionState.authenticated)
  })

  async function enterWorld() {
    const a = getArticle()
    if (!a || !canEnterWorld.value) return
    creatingShardGameId.value = a.game.id
    error.value = ""

    try {
      const data = await api.createShard(a.game.id)
      await router.push({ path: `/world/${data.shard.id}` })
    } catch (err) {
      error.value = err.message
    } finally {
      creatingShardGameId.value = null
    }
  }

  async function toggleGameBookmark() {
    const a = getArticle()
    if (!a?.game) return null

    const nextBookmarked = !a.game.bookmarked
    error.value = ""

    try {
      const data = nextBookmarked
        ? await api.bookmarkNewsGame(a.id)
        : await api.unbookmarkNewsGame(a.id)

      const bookmarked = Boolean(data.game?.bookmarked ?? nextBookmarked)
      const bookmarks_count = data.game?.bookmarks_count

      // Update global store
      if (a.game?.id) newsUi.updateGameBookmark(a.game.id, bookmarked, bookmarks_count)

      return { gameId: a.game.id, bookmarked, bookmarks_count }
    } catch (err) {
      error.value = err.message
      return null
    }
  }

  function gameToggleLabel(game) {
    if (!game) return ""
    return `${game.name} · ${game.bookmarked ? "Выкл" : "Вкл"}`
  }

  function gameFollowersLabel(count) {
    const value = Number(count ?? 0)
    const pr = new Intl.PluralRules("ru-RU")
    const forms = {
      one: "следит",
      few: "следят",
      many: "следят",
      other: "следят"
    }
    return `${value} ${forms[pr.select(value)] || forms.other}`
  }

  return {
    creatingShardGameId,
    error,
    shardTooltip,
    canEnterWorld,
    enterWorld,
    toggleGameBookmark,
    gameToggleLabel,
    gameFollowersLabel
  }
}
