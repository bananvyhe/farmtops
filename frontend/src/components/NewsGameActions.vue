<script setup>
import { toRef } from "vue"
import { useNewsGameActions } from "../composables/useNewsGameActions"

const props = defineProps({
  article: { type: Object, required: true }
})
const articleRef = toRef(props, "article")

const {
  creatingShardGameId,
  shardTooltip,
  canEnterWorld,
  enterWorld,
  toggleGameBookmark,
  gameToggleLabel,
  gameFollowersLabel
} = useNewsGameActions(articleRef)

const emit = defineEmits(["update-bookmark"])

async function handleToggle() {
  const res = await toggleGameBookmark()
  if (res) emit("update-bookmark", res)
}
</script>

<template>
  <div>
    <v-chip
      v-if="article.game"
      size="small"
      :variant="article.game.bookmarked ? 'flat' : 'outlined'"
      :color="article.game.bookmarked ? 'primary' : undefined"
      class="news-card__game-chip"
      @click.stop="handleToggle"
    >
      {{ gameToggleLabel(article.game) }}
    </v-chip>

    <v-chip
      v-if="article.game"
      size="small"
      variant="tonal"
      color="secondary"
      class="news-card__game-count"
    >
      {{ gameFollowersLabel(article.game.bookmarks_count) }}
    </v-chip>

    <v-tooltip :text="shardTooltip" location="top">
      <template #activator="{ props }">
        <span v-bind="props" class="news-card__world-button-wrap" v-if="article.game">
          <button
            v-if="article.game?.can_create_shard"
            class="news-card__world-button"
            type="button"
            :disabled="!canEnterWorld || creatingShardGameId === article.game.id"
            @click.stop.prevent="enterWorld"
          >
            {{ creatingShardGameId === article.game.id ? "Создаем..." : "Войти в мир" }}
          </button>

          <button
            v-else
            class="news-card__world-button news-card__world-button--disabled"
            type="button"
            disabled
          >
            Войти в мир
          </button>
        </span>
      </template>
    </v-tooltip>
  </div>
</template>

<style scoped>
/* component uses classes already present in pages' styles */
</style>
