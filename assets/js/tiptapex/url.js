// URL and CSS value allow-lists — the JS mirror of `Tiptapex.Renderer.URL`.
//
// These back the client-side rendering of header/footer slots, which must
// admit exactly what the server admits: whatever the editor shows you is what
// the exporter will emit.

const ALLOWED_SCHEMES = ["http", "https", "mailto"]
const DATA_IMAGE = /^data:image\/(png|jpe?g|gif|webp|svg\+xml)[;,]/i
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\x00-\x1f\x7f]/

// Simple values: hex colours, keywords, sizes, unquoted font stacks.
const PLAIN_CSS = /^[A-Za-z0-9#,.\s%_-]+$/
// Functional colour notation with strictly numeric arguments.
const COLOR_FN =
  /^(?:rgb|rgba|hsl|hsla)\(\s*\d{1,3}(?:\s*,\s*\d{1,3}(?:\.\d+)?%?){1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$/i

// Absolute http/https/mailto, protocol-relative, or relative. Rejects
// everything else — notably javascript: and data:.
export function safeUrl(url) {
  if (typeof url !== "string") return null
  const trimmed = url.trim()
  if (trimmed === "" || CONTROL_CHARS.test(trimmed)) return null

  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(trimmed)
  if (!scheme) return trimmed
  return ALLOWED_SCHEMES.includes(scheme[1].toLowerCase()) ? trimmed : null
}

// Everything safeUrl accepts, plus `data:` URIs for images — inert in an
// <img>, and the only src Chrome resolves inside a PDF running header.
export function safeImageUrl(url) {
  if (typeof url !== "string") return null
  const trimmed = url.trim()
  if (trimmed === "" || CONTROL_CHARS.test(trimmed)) return null
  if (DATA_IMAGE.test(trimmed)) return trimmed
  return safeUrl(trimmed)
}

// A CSS value for inline style emission. The grammar admits no `;`, braces,
// quotes, `url(` or escapes, so a value cannot break out of its declaration.
export function safeCssValue(value) {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  if (trimmed === "" || trimmed.length > 100) return null
  return PLAIN_CSS.test(trimmed) || COLOR_FN.test(trimmed) ? trimmed : null
}

// Coerces a width/height attribute to integer pixels.
export function intWidth(value) {
  const match = /^\s*(\d+)(px)?\s*$/.exec(String(value ?? ""))
  if (!match) return null
  const pixels = parseInt(match[1], 10)
  return pixels > 0 ? pixels : null
}
