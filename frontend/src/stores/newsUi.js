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
    updateGameBookmark(gameId, bookmarked) {
      if (!this.feedSnapshot?.articles?.length) return

      const nextArticles = this.feedSnapshot.articles.map((article) => {
        if (article.game?.id !== gameId) return article

        return {
          ...article,
          game: {
            ...article.game,
            bookmarked
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
