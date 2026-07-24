// Page geometry shared by the page-setup extension, the pagination plugin
// and the page-setup dialog. It is the JS mirror of `Tiptapex.Page`: same
// presets, same normalisation rules, same JSON shape — because that JSON is
// what travels in the document's `attrs.page` and is read back by the
// server-side exporter.
//
// Every length is a number of MILLIMETRES. Strings carrying a CSS unit
// ("1in", "2.5cm", "72pt", "96px") are accepted and converted.

import { safeImageUrl } from "./url"

// Portrait dimensions, in millimetres.
export const PAGE_PRESETS = {
  letter: [215.9, 279.4],
  legal: [215.9, 355.6],
  tabloid: [279.4, 431.8],
  executive: [184.15, 266.7],
  a3: [297, 420],
  a4: [210, 297],
  a5: [148, 210],
}

export const DEFAULT_MARGIN = 25.4

const SLOTS = ["left", "center", "right"]
const TOKEN_RE = /\{(page|pages|date|time|title)\}/g
const MAX_SLOT_LENGTH = 500

export const DEFAULT_IMAGE_HEIGHT = 8
const MAX_IMAGE_HEIGHT = 100

// CSS reference pixels per millimetre (96 dpi).
export const PX_PER_MM = 96 / 25.4

export function mmToPx(mm) {
  return mm * PX_PER_MM
}

export function pxToMm(px) {
  return px / PX_PER_MM
}

export function defaultPage() {
  return {
    size: "letter",
    orientation: "portrait",
    margins: { top: DEFAULT_MARGIN, right: DEFAULT_MARGIN, bottom: DEFAULT_MARGIN, left: DEFAULT_MARGIN },
    header: emptyRegion(),
    footer: emptyRegion(),
    numbering: { enabled: false, region: "footer", align: "center", format: "{page}" },
    title: null,
  }
}

function toMm(value, fallback) {
  if (typeof value === "number" && isFinite(value)) return value
  if (typeof value === "string") {
    const m = /^\s*(-?\d+(?:\.\d+)?)\s*(mm|cm|in|pt|px)?\s*$/i.exec(value)
    if (m) {
      const n = parseFloat(m[1])
      switch ((m[2] || "mm").toLowerCase()) {
        case "cm": return n * 10
        case "in": return n * 25.4
        case "pt": return (n * 25.4) / 72
        case "px": return (n * 25.4) / 96
        default: return n
      }
    }
  }
  return fallback
}

function text(value) {
  return typeof value === "string" ? value.slice(0, MAX_SLOT_LENGTH) : ""
}

function normalizeSize(size) {
  if (typeof size === "string" && PAGE_PRESETS[size.toLowerCase()]) return size.toLowerCase()
  if (size && typeof size === "object") {
    const width = toMm(size.width, NaN)
    const height = toMm(size.height, NaN)
    if (width > 0 && height > 0) return { width, height }
  }
  return "letter"
}

function emptyRegion() {
  const out = {}
  SLOTS.forEach((slot) => {
    out[slot] = { text: "", image: null }
  })
  return out
}

function normalizeImage(image) {
  if (!image || typeof image !== "object") return null

  // Same allow-list as `Tiptapex.Renderer.URL.safe_image_url/1`.
  const src = safeImageUrl(image?.src)
  if (!src) return null

  const height = toMm(image.height, DEFAULT_IMAGE_HEIGHT)

  return {
    src,
    alt: text(image.alt),
    height: Math.min(height > 0 ? height : DEFAULT_IMAGE_HEIGHT, MAX_IMAGE_HEIGHT),
  }
}

// A slot is a bare string (text only) or a map carrying text and/or an image.
function normalizeSlot(value) {
  if (typeof value === "string") return { text: text(value), image: null }
  if (value && typeof value === "object") {
    return { text: text(value.text), image: normalizeImage(value.image) }
  }
  return { text: "", image: null }
}

function normalizeRegion(region) {
  const source = region && typeof region === "object" ? region : {}
  const out = {}
  SLOTS.forEach((slot) => {
    out[slot] = normalizeSlot(source[slot])
  })
  return out
}

// Accepts anything (stored JSON, a partial object from the dialog, null) and
// returns a complete, well-formed page object — or null for "not paginated".
export function normalizePage(input) {
  if (input == null || input === false) return null
  const source = input === true ? {} : input
  if (typeof source !== "object") return null

  const base = defaultPage()
  const margins = source.margins && typeof source.margins === "object" ? source.margins : {}
  const numbering = source.numbering && typeof source.numbering === "object" ? source.numbering : {}

  return {
    size: normalizeSize(source.size),
    orientation: source.orientation === "landscape" ? "landscape" : "portrait",
    margins: {
      top: Math.max(0, toMm(margins.top, base.margins.top)),
      right: Math.max(0, toMm(margins.right, base.margins.right)),
      bottom: Math.max(0, toMm(margins.bottom, base.margins.bottom)),
      left: Math.max(0, toMm(margins.left, base.margins.left)),
    },
    header: normalizeRegion(source.header),
    footer: normalizeRegion(source.footer),
    numbering: {
      enabled: numbering.enabled === true,
      region: numbering.region === "header" ? "header" : "footer",
      align: numbering.align === "left" || numbering.align === "right" ? numbering.align : "center",
      format: text(numbering.format) || "{page}",
    },
    title: typeof source.title === "string" && source.title !== "" ? source.title : null,
  }
}

// Deep-merges a partial patch (what the dialog produces) onto a page object.
export function mergePage(page, patch) {
  const base = normalizePage(page) || defaultPage()
  if (!patch || typeof patch !== "object") return base
  const merged = { ...base, ...patch }
  for (const key of ["margins", "header", "footer", "numbering"]) {
    if (patch[key] && typeof patch[key] === "object") {
      merged[key] = { ...base[key], ...patch[key] }
    }
  }
  return normalizePage(merged)
}

// Paper size in millimetres, with orientation applied.
export function pageDimensions(page) {
  const size = page.size
  const [w, h] = typeof size === "string" ? PAGE_PRESETS[size] || PAGE_PRESETS.letter : [size.width, size.height]
  return page.orientation === "landscape" ? { width: h, height: w } : { width: w, height: h }
}

// Everything the pagination plugin and the stylesheet need, in CSS pixels.
export function pageGeometry(page) {
  const { width, height } = pageDimensions(page)
  const m = page.margins
  const pageWidth = mmToPx(width)
  const pageHeight = mmToPx(height)
  const top = mmToPx(m.top)
  const right = mmToPx(m.right)
  const bottom = mmToPx(m.bottom)
  const left = mmToPx(m.left)

  return {
    pageWidth,
    pageHeight,
    top,
    right,
    bottom,
    left,
    contentWidth: Math.max(pageWidth - left - right, 0),
    // A page with margins so large nothing fits would make the paginator
    // loop; keep at least one CSS pixel of content box.
    contentHeight: Math.max(pageHeight - top - bottom, 1),
  }
}

// The three slots of a region — `{slot, text, image}` — with page numbering
// merged into the text. Mirrors `Tiptapex.Page.slots/2`.
export function pageSlots(page, region) {
  const base = { ...page[region] }
  const n = page.numbering

  if (n.enabled && n.region === region) {
    const slot = base[n.align]
    let merged = slot.text
    if (merged === "") merged = n.format
    else if (!merged.includes("{page}")) merged = `${merged} ${n.format}`
    base[n.align] = { ...slot, text: merged }
  }

  return SLOTS.map((slot) => ({ slot, ...base[slot] }))
}

export function regionUsed(page, region) {
  return pageSlots(page, region).some((slot) => slot.text !== "" || slot.image)
}

// A stable key for everything the running header/footer draws. The paginator
// folds it into its signature so a logo or a footer edit re-renders the gaps,
// which are otherwise keyed only by geometry.
export function runningKey(page) {
  return JSON.stringify([page.header, page.footer, page.numbering, page.title])
}

export function replaceTokens(value, replacements) {
  return value.replace(TOKEN_RE, (_match, token) => replacements[token] ?? "")
}

// Resolves the page setup for a freshly mounted editor/viewer: an explicit
// `page` attribute on the component wins over whatever the stored document
// carries, and `page={false}` clears it. Returns a *new* document — the one
// passed in may be a shared constant (EMPTY_DOC) that must not be mutated.
export function resolvePageSetup(doc, page) {
  if (page === undefined || page === null) return { doc, page: doc?.attrs?.page ?? null }

  const resolved = page === false ? null : page
  return { doc: { ...doc, attrs: { ...(doc?.attrs || {}), page: resolved } }, page: resolved }
}

// Token values for the live preview inside the editor. `{pages}` is the
// measured page count, so the preview stays honest while you type.
export function previewTokens({ page, pages, title, locale }) {
  const now = new Date()
  return {
    page: String(page),
    pages: String(pages),
    date: now.toLocaleDateString(locale),
    time: now.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" }),
    title: title || "",
  }
}
