import "vuetify/styles"
import { createVuetify } from "vuetify"
import { aliases, mdi } from "vuetify/iconsets/mdi"
import "@mdi/font/css/materialdesignicons.css"

const farmspotTheme = {
  dark: false,
  colors: {
    primary: "#c75923",
    secondary: "#7d6757",
    background: "#f5ead8",
    surface: "#fff9f1",
    error: "#9b3124",
    warning: "#c77f2c",
    info: "#2f5f9e",
    success: "#3f7d4d"
  }
}

export default createVuetify({
  icons: {
    defaultSet: "mdi",
    aliases,
    sets: {
      mdi
    }
  },
  theme: {
    defaultTheme: "farmspot",
    themes: {
      farmspot: farmspotTheme
    }
  }
})
