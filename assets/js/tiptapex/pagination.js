// Live pagination for the Tiptapex editor.
//
// When the document carries a page setup (`doc.attrs.page`, see
// `./extensions/page-setup`), this plugin turns the continuous editing
// surface into a stack of sheets: it measures the rendered blocks, works out
// where each page ends, and inserts a widget decoration that fills the rest
// of the page, draws the running footer, the gap between sheets and the next
// page's running header.
//
// Everything is decoration + sibling DOM — the document is never modified, so
// undo/redo, collaboration and the JSON you persist stay untouched.
//
// The DOM it builds around the ProseMirror element:
//
//   .ttx-content.ttx-paged
//     .ttx-page-stack          — the sheet: width and CSS vars live here
//       .ttx-page-head         — page 1's top margin + running header
//       .ProseMirror           — the content, with the side margins as padding
//         …blocks…
//         .ttx-page-gap        — widget: footer · gutter · next header
//         …blocks…
//       .ttx-page-tail         — the rest of the last page + running footer
import { Extension } from "@tiptap/core"
import { Plugin, PluginKey } from "@tiptap/pm/state"
import { Decoration, DecorationSet } from "@tiptap/pm/view"

import { renderMarkup } from "./markup"
import { mmToPx, normalizePage, pageGeometry, pageSlots, previewTokens, replaceTokens, runningKey } from "./page"

export const paginationKey = new PluginKey("tiptapexPagination")

export const DEFAULT_PAGINATION_LABELS = {
  pageBreak: "Page break",
  removePageBreak: "Remove page break",
}

// Vertical space between two sheets, in CSS pixels.
const DEFAULT_GUTTER = 28

export const Pagination = Extension.create({
  name: "tiptapexPagination",

  addOptions() {
    return {
      gutter: DEFAULT_GUTTER,
      labels: {},
      // Locale for the {date}/{time} preview tokens; undefined = browser.
      locale: undefined,
      // Called with the measured page count whenever it changes.
      onPages: null,
    }
  },

  addStorage() {
    return { pages: 1 }
  },

  addProseMirrorPlugins() {
    const editor = this.editor
    const options = this.options
    const storage = this.storage

    return [
      new Plugin({
        key: paginationKey,

        state: {
          init: () => ({ decorations: DecorationSet.empty, signature: "", pages: 1 }),
          apply(tr, value) {
            const meta = tr.getMeta(paginationKey)
            if (meta) return meta
            // Keep the existing gaps roughly in place until the next
            // measurement lands, so typing doesn't make the sheets flicker.
            if (tr.docChanged) {
              return { ...value, decorations: value.decorations.map(tr.mapping, tr.doc) }
            }
            return value
          },
        },

        props: {
          decorations(state) {
            return paginationKey.getState(state).decorations
          },
        },

        view: (view) => new PaginationView(view, editor, options, storage),
      }),
    ]
  },
})

class PaginationView {
  constructor(view, editor, options, storage) {
    this.view = view
    this.editor = editor
    this.options = options
    this.storage = storage
    this.labels = { ...DEFAULT_PAGINATION_LABELS, ...(options.labels || {}) }
    this.frame = null
    this.stack = null
    this.head = null
    this.tail = null
    this.pages = 1

    this.onResize = () => this.schedule()
    window.addEventListener("resize", this.onResize)

    // Catches everything a transaction doesn't: images finishing their load,
    // web fonts swapping in, a table column being dragged.
    if (typeof ResizeObserver !== "undefined") {
      this.observer = new ResizeObserver(() => this.schedule())
      this.observer.observe(view.dom)
    }

    this.schedule()
  }

  update() {
    this.schedule()
  }

  schedule() {
    if (this.frame != null) return
    this.frame = window.requestAnimationFrame(() => {
      this.frame = null
      try {
        this.measure()
      } catch (e) {
        console.error("[Tiptapex] pagination failed:", e)
      }
    })
  }

  measure() {
    const view = this.view
    if (!view || view.isDestroyed || !view.dom.isConnected) return

    const page = normalizePage(view.state.doc.attrs?.page)
    if (!page) {
      this.unmountChrome()
      this.publish(DecorationSet.empty, "", 1)
      return
    }

    const geom = pageGeometry(page)
    const gutter = Math.max(0, this.options.gutter ?? DEFAULT_GUTTER)

    this.mountChrome()
    if (!this.stack) return
    this.applyGeometry(geom, gutter)

    const { breaks, used, pages } = computeBreaks(this.collectBlocks(), geom)

    const ctx = {
      page,
      geom,
      gutter,
      pages,
      labels: this.labels,
      locale: this.options.locale,
      // Folded into the decoration key so editing a header, a footer or a
      // logo rebuilds the gaps — geometry alone would not have changed.
      runningKey: runningKey(page),
    }

    // Page 1's header, and the fill + footer of the last page.
    this.renderRunner(this.head, ctx, "header", 1, geom.top)
    const tailFill = Math.max(geom.contentHeight - used, 0)
    this.tail.style.height = `${tailFill + geom.bottom}px`
    this.renderRunner(this.tail, ctx, "footer", pages, geom.bottom)

    const decorations = DecorationSet.create(
      view.state.doc,
      breaks.map((brk, index) =>
        Decoration.widget(brk.pos, (widgetView, getPos) => renderGap(brk, index, ctx, widgetView, getPos), {
          side: -1,
          // Encodes everything the gap's DOM depends on, so ProseMirror
          // rebuilds it exactly when it has to.
          key:
            `ttx-gap-${index}-${Math.round(brk.fill)}-${pages}-${brk.forced ? "f" : "a"}` +
            `-${hash(ctx.runningKey)}`,
          ignoreSelection: true,
          stopEvent: () => true,
        })
      )
    )

    this.publish(decorations, signatureOf(breaks, pages, geom, ctx.runningKey), pages)
  }

  // Top-level blocks with the metrics the paginator needs. Top margins are
  // zeroed in paged mode (see `.ttx-paged` in the stylesheet) so block
  // heights simply add up — no margin collapsing to reason about.
  collectBlocks() {
    const view = this.view
    const blocks = []

    view.state.doc.forEach((node, offset) => {
      const dom = view.nodeDOM(offset)
      if (!dom || dom.nodeType !== 1) return
      blocks.push({
        pos: offset,
        isBreak: node.type.name === "pageBreak",
        height: dom.getBoundingClientRect().height,
        gap: parseFloat(window.getComputedStyle(dom).marginBottom) || 0,
      })
    })

    return blocks
  }

  publish(decorations, signature, pages) {
    const current = paginationKey.getState(this.view.state)
    if (current && current.signature === signature) return

    this.view.dispatch(this.view.state.tr.setMeta(paginationKey, { decorations, signature, pages }))

    if (this.pages !== pages) {
      this.pages = pages
      this.storage.pages = pages
      this.options.onPages?.(pages)
    }
  }

  mountChrome() {
    if (this.stack) return
    const dom = this.view.dom
    const parent = dom.parentNode
    if (!parent) return

    this.stack = document.createElement("div")
    this.stack.className = "ttx-page-stack"

    this.head = document.createElement("div")
    this.head.className = "ttx-page-head"
    this.head.contentEditable = "false"

    this.tail = document.createElement("div")
    this.tail.className = "ttx-page-tail"
    this.tail.contentEditable = "false"

    parent.insertBefore(this.stack, dom)
    this.stack.appendChild(this.head)
    this.stack.appendChild(dom)
    this.stack.appendChild(this.tail)
    parent.classList.add("ttx-paged")
  }

  unmountChrome() {
    if (!this.stack) return
    const dom = this.view.dom
    const parent = this.stack.parentNode
    if (parent) {
      parent.insertBefore(dom, this.stack)
      parent.classList.remove("ttx-paged")
    }
    this.stack.remove()
    this.stack = null
    this.head = null
    this.tail = null
  }

  applyGeometry(geom, gutter) {
    const style = this.stack.style
    style.setProperty("--ttx-page-w", `${geom.pageWidth}px`)
    style.setProperty("--ttx-page-h", `${geom.pageHeight}px`)
    style.setProperty("--ttx-page-mt", `${geom.top}px`)
    style.setProperty("--ttx-page-mr", `${geom.right}px`)
    style.setProperty("--ttx-page-mb", `${geom.bottom}px`)
    style.setProperty("--ttx-page-ml", `${geom.left}px`)
    style.setProperty("--ttx-page-gutter", `${gutter}px`)
    this.head.style.height = `${geom.top}px`
  }

  // Replaces the runner row of a chrome element (head/tail) in place.
  renderRunner(host, ctx, region, pageNumber, height) {
    host.querySelector(":scope > .ttx-page-runner")?.remove()
    host.appendChild(runner(ctx, region, pageNumber, height))
  }

  destroy() {
    if (this.frame != null) window.cancelAnimationFrame(this.frame)
    window.removeEventListener("resize", this.onResize)
    this.observer?.disconnect()
    this.unmountChrome()
  }
}

// Walks the blocks filling one page after another. `fill` is the leftover
// space at the bottom of the page the break closes.
export function computeBreaks(blocks, geom) {
  const contentHeight = geom.contentHeight
  const breaks = []
  let used = 0
  let extraPages = 0

  for (const block of blocks) {
    if (block.isBreak) {
      // Consecutive breaks (and one at the very top) collapse, matching how
      // browsers treat `break-after: page`.
      if (used > 0) {
        breaks.push({ pos: block.pos, fill: contentHeight - used, forced: true })
        used = 0
      }
      continue
    }

    if (used > 0 && used + block.height > contentHeight) {
      breaks.push({ pos: block.pos, fill: contentHeight - used, forced: false })
      used = 0
    }

    used += block.height

    // A single block taller than the page (a long table, a huge image) just
    // flows across the sheets below it. Only the block's own height can do
    // this — a trailing margin that doesn't fit is swallowed by the page
    // boundary, it never carries content onto the next sheet.
    while (used > contentHeight) {
      used -= contentHeight
      extraPages += 1
    }

    used = Math.min(used + block.gap, contentHeight)
  }

  return { breaks, used, pages: breaks.length + extraPages + 1 }
}

function signatureOf(breaks, pages, geom, running) {
  return `${pages}|${Math.round(geom.pageHeight)}x${Math.round(geom.contentHeight)}|${hash(running)}|${breaks
    .map((b) => `${b.pos}:${Math.round(b.fill)}:${b.forced ? 1 : 0}`)
    .join(",")}`
}

// djb2 — short, stable, and only ever compared against itself.
function hash(value) {
  let h = 5381
  for (let i = 0; i < value.length; i++) h = ((h << 5) + h + value.charCodeAt(i)) | 0
  return (h >>> 0).toString(36)
}

// ---------------------------------------------------------------------------
// Gap + running header/footer DOM
// ---------------------------------------------------------------------------

function div(className, height) {
  const el = document.createElement("div")
  el.className = className
  if (height != null) el.style.height = `${height}px`
  return el
}

function runner(ctx, region, pageNumber, height) {
  const el = div(`ttx-page-runner ttx-page-runner-${region}`, height)
  const tokens = previewTokens({
    page: pageNumber,
    pages: ctx.pages,
    title: ctx.page.title,
    locale: ctx.locale,
  })

  pageSlots(ctx.page, region).forEach(({ slot, text, image }) => {
    const cell = div(`ttx-page-slot is-${slot}`)

    if (image) {
      // `src` was validated by normalizePage; the element is built, never
      // interpolated into markup.
      const img = document.createElement("img")
      img.src = image.src
      img.alt = image.alt
      img.style.height = `${mmToPx(image.height)}px`
      cell.appendChild(img)
    }

    const resolved = replaceTokens(text, tokens)
    if (resolved !== "") {
      // Slots are user input: renderMarkup rebuilds the allow-listed subset
      // out of createElement/createTextNode. There is no innerHTML here.
      cell.appendChild(renderMarkup(resolved, document.createElement("span")))
    }

    el.appendChild(cell)
  })

  return el
}

function renderGap(brk, index, ctx, view, getPos) {
  const { geom, gutter, pages } = ctx
  const fill = Math.max(brk.fill, 0)
  const closes = index + 1

  const el = document.createElement("div")
  el.className = "ttx-page-gap"
  el.contentEditable = "false"
  el.setAttribute("data-ttx-page-gap", String(closes))

  const foot = div("ttx-page-gap-foot", fill + geom.bottom)
  foot.appendChild(runner(ctx, "footer", closes, geom.bottom))

  const space = div("ttx-page-gap-space", gutter)
  if (brk.forced) space.appendChild(breakChip(ctx, view, getPos))

  const head = div("ttx-page-gap-head", geom.top)
  head.appendChild(runner(ctx, "header", Math.min(closes + 1, pages), geom.top))

  el.appendChild(foot)
  el.appendChild(space)
  el.appendChild(head)
  return el
}

// A forced break is invisible in paged mode (the gap *is* the break), so the
// gutter carries a chip that says so — and removes it on click.
function breakChip(ctx, view, getPos) {
  const chip = document.createElement("button")
  chip.type = "button"
  chip.className = "ttx-page-break-chip"
  chip.textContent = ctx.labels.pageBreak
  chip.title = ctx.labels.removePageBreak
  chip.setAttribute("aria-label", ctx.labels.removePageBreak)

  chip.addEventListener("mousedown", (event) => {
    event.preventDefault()
    event.stopPropagation()

    const pos = getPos()
    if (pos == null) return
    const node = view.state.doc.nodeAt(pos)
    if (!node || node.type.name !== "pageBreak") return
    view.dispatch(view.state.tr.delete(pos, pos + node.nodeSize))
  })

  return chip
}
