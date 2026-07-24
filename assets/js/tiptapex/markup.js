// A small allow-listed HTML subset for header/footer slots — the JS mirror of
// `Tiptapex.Renderer.Markup`, so the editor's running header shows exactly
// what the PDF will contain.
//
// Same rule as the server: nothing from the input is ever interpreted as
// markup unless it matches the closed allow-list. There is no `innerHTML`
// here — the string is tokenised and rebuilt with `createElement` and
// `createTextNode`, so an unknown or malformed tag becomes visible text
// rather than a script.
import { intWidth, safeCssValue, safeImageUrl, safeUrl } from "./url"

const INLINE = ["b", "strong", "i", "em", "u", "s", "small", "sub", "sup", "span", "a", "br", "img"]
const BLOCK = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6"]
const VOID = new Set(["br", "img"])
const ALLOWED = new Set([...INLINE, ...BLOCK])

const STYLE_PROPERTIES = new Set([
  "color",
  "background-color",
  "font-size",
  "font-weight",
  "font-style",
  "font-family",
  "text-decoration",
  "text-transform",
  "letter-spacing",
  "line-height",
  "opacity",
  "vertical-align",
  "padding",
  "margin",
])

// A tag is only a tag if it matches exactly this shape: a plausible name and
// double-quoted attribute values with no angle brackets.
const TAG = /^<(\/?)([a-zA-Z][a-zA-Z0-9]{0,9})((?:\s+[a-zA-Z-]{1,20}\s*=\s*"[^"<>]*")*)\s*(\/?)>$/
const ATTRIBUTE = /([a-zA-Z-]{1,20})\s*=\s*"([^"<>]*)"/g

export const ALLOWED_TAGS = [...ALLOWED]

function tokenize(text) {
  return text.split(/(<[^<>]*>)/).filter((token) => token !== "")
}

function classify(token) {
  if (token[0] !== "<") return { kind: "text", text: token }

  const match = TAG.exec(token)
  if (!match) return { kind: "text", text: token }

  const [, closing, name, rawAttributes, selfClosing] = match
  const tag = name.toLowerCase()
  if (!ALLOWED.has(tag)) return { kind: "text", text: token }

  if (closing === "/") return { kind: "close", tag }
  const attributes = parseAttributes(tag, rawAttributes)

  return VOID.has(tag) || selfClosing === "/"
    ? { kind: "void", tag, attributes }
    : { kind: "open", tag, attributes }
}

function parseAttributes(tag, raw) {
  const out = []
  let match

  ATTRIBUTE.lastIndex = 0
  while ((match = ATTRIBUTE.exec(raw)) !== null) {
    const name = match[1].toLowerCase()
    const value = match[2]

    if (name === "style") {
      const style = safeStyle(value)
      if (style) out.push(["style", style])
    } else if (name === "title") {
      out.push(["title", value])
    } else if (tag === "a" && name === "href") {
      const href = safeUrl(value)
      if (href) out.push(["href", href], ["rel", "noopener nofollow"])
    } else if (tag === "img" && name === "src") {
      const src = safeImageUrl(value)
      if (src) out.push(["src", src])
    } else if (tag === "img" && name === "alt") {
      out.push(["alt", value])
    } else if (tag === "img" && (name === "width" || name === "height")) {
      const pixels = intWidth(value)
      if (pixels) out.push([name, String(pixels)])
    }
  }

  return out
}

// Declarations are validated one at a time and rebuilt.
function safeStyle(value) {
  const declarations = []

  for (const declaration of value.split(";")) {
    const index = declaration.indexOf(":")
    if (index === -1) continue

    const property = declaration.slice(0, index).trim().toLowerCase()
    if (!STYLE_PROPERTIES.has(property)) continue

    const cssValue = safeCssValue(declaration.slice(index + 1))
    if (cssValue) declarations.push(`${property}: ${cssValue}`)
  }

  return declarations.length > 0 ? declarations.join("; ") : null
}

function build(token) {
  const element = document.createElement(token.tag)
  token.attributes.forEach(([name, value]) => element.setAttribute(name, value))
  return element
}

/**
 * Appends the allow-listed rendering of `text` into `target`, and returns it.
 * Unclosed tags simply stay open — the DOM handles that for us.
 */
export function renderMarkup(text, target) {
  if (typeof text !== "string" || text === "") return target

  const stack = [target]

  for (const raw of tokenize(text)) {
    const token = classify(raw)
    const parent = stack[stack.length - 1]

    if (token.kind === "text") {
      parent.appendChild(document.createTextNode(token.text))
    } else if (token.kind === "void") {
      parent.appendChild(build(token))
    } else if (token.kind === "open") {
      const element = build(token)
      parent.appendChild(element)
      stack.push(element)
    } else if (stack.length > 1 && parent.localName === token.tag) {
      // A closer that doesn't match the innermost element is dropped.
      stack.pop()
    }
  }

  return target
}

/** True when `text` contains at least one tag this module would render. */
export function hasMarkup(text) {
  if (typeof text !== "string") return false
  return tokenize(text).some((token) => classify(token).kind !== "text")
}
