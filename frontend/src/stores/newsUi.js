import { defineStore } from "pinia"

export const useNewsUiStore = defineStore("newsUi", {
  state: () => ({
    feedSnapshot: null
  }),
  actions: {
    saveFeedSnapshot(snapshot) {
      this.feedSnapshot = snapshot
    },
    clearFeedSnapshot() {
      this.feedSnapshot = null
    },
    updateGameBookmark(gameId, bookmarked, bookmarksCount) {
      this.updateGameState(gameId, {
        bookmarked,
        ...(typeof bookmarksCount === "number" ? {
          bookmarks_count: bookmarksCount,
          can_create_shard: bookmarksCount > 0
        } : {})
      })
    },
    updateGameState(gameId, gamePatch) {
      if (!this.feedSnapshot?.articles?.length) return

      const nextArticles = this.feedSnapshot.articles.map((article) => {
        if (article.game?.id !== gameId) return article

        return {
          ...article,
          game: {
            ...article.game,
            ...gamePatch
          }
        }
      })

      this.feedSnapshot = {
        ...this.feedSnapshot,
        articles: nextArticles
      }
    }
  }
})
