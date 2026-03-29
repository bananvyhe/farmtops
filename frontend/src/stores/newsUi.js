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
    }
  }
})
