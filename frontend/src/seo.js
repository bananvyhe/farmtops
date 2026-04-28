const SITE_NAME = "Farmspot"
const FALLBACK_ORIGIN = "https://farmspot.ru"
const DEFAULT_DESCRIPTION = "Farmspot — новости, личный кабинет, миры и админка проекта."

function getSiteOrigin() {
  if (import.meta.env.PROD) {
    return import.meta.env.VITE_SITE_URL || FALLBACK_ORIGIN
  }

  if (typeof window !== "undefined" && window.location?.origin) {
    return window.location.origin
  }

  return import.meta.env.VITE_SITE_URL || FALLBACK_ORIGIN
}

function getAbsoluteUrl(pathname = "/") {
  return new URL(pathname, getSiteOrigin()).toString()
}

function ensureElement(selector, createElement) {
  let element = document.head.querySelector(selector)
  if (!element) {
    element = createElement()
    document.head.appendChild(element)
  }

  return element
}

function setMetaTag(selector, attributes) {
  const element = ensureElement(selector, () => document.createElement("meta"))
  Object.entries(attributes).forEach(([key, value]) => {
    element.setAttribute(key, value)
  })
}

function setLinkTag(selector, attributes) {
  const element = ensureElement(selector, () => document.createElement("link"))
  Object.entries(attributes).forEach(([key, value]) => {
    element.setAttribute(key, value)
  })
}

function removeMetaTag(selector) {
  document.head.querySelector(selector)?.remove()
}

function normalizeDescription(value) {
  const trimmed = String(value || "").trim()
  if (!trimmed) return DEFAULT_DESCRIPTION
  return trimmed.length > 180 ? `${trimmed.slice(0, 177)}...` : trimmed
}

export function setSeo({
  title,
  description,
  canonicalPath,
  robots = "index, follow",
  type = "website",
  image,
  publishedTime,
  modifiedTime,
  keywords,
  articleTags
} = {}) {
  if (typeof document === "undefined") return

  const resolvedTitle = title ? `${title} · ${SITE_NAME}` : SITE_NAME
  const resolvedDescription = normalizeDescription(description)
  const resolvedCanonical = getAbsoluteUrl(canonicalPath || window.location.pathname)

  document.title = resolvedTitle
  setMetaTag('meta[name="description"]', { name: "description", content: resolvedDescription })
  setMetaTag('meta[name="robots"]', { name: "robots", content: robots })
  setMetaTag('meta[property="og:site_name"]', { property: "og:site_name", content: SITE_NAME })
  setMetaTag('meta[property="og:title"]', { property: "og:title", content: resolvedTitle })
  setMetaTag('meta[property="og:description"]', { property: "og:description", content: resolvedDescription })
  setMetaTag('meta[property="og:url"]', { property: "og:url", content: resolvedCanonical })
  setMetaTag('meta[property="og:type"]', { property: "og:type", content: type })
  setMetaTag('meta[name="twitter:card"]', { name: "twitter:card", content: image ? "summary_large_image" : "summary" })
  setMetaTag('meta[name="twitter:title"]', { name: "twitter:title", content: resolvedTitle })
  setMetaTag('meta[name="twitter:description"]', { name: "twitter:description", content: resolvedDescription })
  setLinkTag('link[rel="canonical"]', { rel: "canonical", href: resolvedCanonical })

  const resolvedKeywords = Array.isArray(keywords)
    ? keywords
    : String(keywords || "")
        .split(",")
        .map((value) => value.trim())
  const normalizedKeywords = [...new Set(resolvedKeywords.map((value) => String(value || "").trim()).filter(Boolean))]
  if (normalizedKeywords.length) {
    setMetaTag('meta[name="keywords"]', {
      name: "keywords",
      content: normalizedKeywords.join(", ")
    })
  } else {
    removeMetaTag('meta[name="keywords"]')
  }

  document.head.querySelectorAll('meta[property="article:tag"]').forEach((element) => element.remove())
  const resolvedArticleTags = Array.isArray(articleTags)
    ? articleTags
    : String(articleTags || "")
        .split(",")
        .map((value) => value.trim())
  const normalizedArticleTags = [...new Set(resolvedArticleTags.map((value) => String(value || "").trim()).filter(Boolean))]
  normalizedArticleTags.forEach((value) => {
    const element = document.createElement("meta")
    element.setAttribute("property", "article:tag")
    element.setAttribute("content", value)
    document.head.appendChild(element)
  })

  if (image) {
    const resolvedImage = image.startsWith("http") ? image : getAbsoluteUrl(image)
    setMetaTag('meta[property="og:image"]', { property: "og:image", content: resolvedImage })
    setMetaTag('meta[name="twitter:image"]', { name: "twitter:image", content: resolvedImage })
  } else {
    removeMetaTag('meta[property="og:image"]')
    removeMetaTag('meta[name="twitter:image"]')
  }

  if (publishedTime) {
    setMetaTag('meta[property="article:published_time"]', {
      property: "article:published_time",
      content: new Date(publishedTime).toISOString()
    })
  } else {
    removeMetaTag('meta[property="article:published_time"]')
  }

  if (modifiedTime) {
    setMetaTag('meta[property="article:modified_time"]', {
      property: "article:modified_time",
      content: new Date(modifiedTime).toISOString()
    })
  } else {
    removeMetaTag('meta[property="article:modified_time"]')
  }
}
