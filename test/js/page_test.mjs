import assert from "node:assert/strict"

import { test } from "./harness.mjs"
import {
  normalizePage,
  mergePage,
  pageDimensions,
  pageGeometry,
  pageSlots,
  regionUsed,
  replaceTokens,
  resolvePageSetup,
  runningKey,
  defaultPage,
} from "tiptapex/page"

const t = (name, fn) => test("page", name, fn)

t("normalizePage(null) means not paginated", () => {
  assert.equal(normalizePage(null), null)
  assert.equal(normalizePage(false), null)
  assert.equal(normalizePage(undefined), null)
})

t("normalizePage(true) is the default page", () => {
  assert.deepEqual(normalizePage(true), defaultPage())
})

t("defaults match Tiptapex.Page: letter, portrait, 1in margins", () => {
  const p = normalizePage({})
  assert.equal(p.size, "letter")
  assert.equal(p.orientation, "portrait")
  assert.deepEqual(p.margins, { top: 25.4, right: 25.4, bottom: 25.4, left: 25.4 })
  assert.equal(p.numbering.enabled, false)
  assert.equal(p.numbering.format, "{page}")
})

t("CSS units are converted to millimetres", () => {
  const p = normalizePage({ margins: { top: "1in", right: "2cm", bottom: "36pt", left: "96px" } })
  assert.equal(p.margins.top, 25.4)
  assert.equal(p.margins.right, 20)
  assert.ok(Math.abs(p.margins.bottom - 12.7) < 1e-9)
  assert.ok(Math.abs(p.margins.left - 25.4) < 1e-9, "96px is one inch, modulo float noise")
})

t("junk falls back instead of throwing", () => {
  const p = normalizePage({
    size: "papyrus",
    orientation: "sideways",
    margins: { top: "wat" },
    header: { left: 42 },
    numbering: { enabled: "yes", align: "middle", format: "" },
  })
  assert.equal(p.size, "letter")
  assert.equal(p.orientation, "portrait")
  assert.equal(p.margins.top, 25.4)
  assert.deepEqual(p.header.left, { text: "", image: null })
  assert.equal(p.numbering.enabled, false)
  assert.equal(p.numbering.align, "center")
  assert.equal(p.numbering.format, "{page}")
})

t("landscape swaps the axes, like Tiptapex.Page.dimensions/1", () => {
  assert.deepEqual(pageDimensions(normalizePage({ size: "letter", orientation: "landscape" })), {
    width: 279.4,
    height: 215.9,
  })
  assert.deepEqual(pageDimensions(normalizePage({ size: "legal" })), { width: 215.9, height: 355.6 })
})

t("geometry converts to CSS pixels at 96dpi", () => {
  const g = pageGeometry(normalizePage({ size: "letter" }))
  assert.equal(Math.round(g.pageWidth), 816) // 8.5in
  assert.equal(Math.round(g.pageHeight), 1056) // 11in
  assert.equal(Math.round(g.top), 96)
  assert.equal(Math.round(g.contentHeight), 864) // 11in - 2in
})

t("a content box crushed by margins still leaves a pixel — no infinite loop", () => {
  const g = pageGeometry(normalizePage({ size: "a5", margins: { top: 200, bottom: 200 } }))
  assert.ok(g.contentHeight >= 1)
})

t("mergePage deep-merges a patch", () => {
  const base = normalizePage({ size: "legal", margins: { top: 10 } })
  const merged = mergePage(base, { orientation: "landscape", margins: { bottom: 5 } })
  assert.equal(merged.size, "legal")
  assert.equal(merged.orientation, "landscape")
  assert.equal(merged.margins.top, 10)
  assert.equal(merged.margins.bottom, 5)
})

t("slots place numbering exactly like Tiptapex.Page.slots/2", () => {
  const p = normalizePage({
    footer: { center: "Confidential" },
    numbering: { enabled: true, region: "footer", align: "center", format: "{page}" },
  })
  assert.deepEqual(pageSlots(p, "footer"), [
    { slot: "left", text: "", image: null },
    { slot: "center", text: "Confidential {page}", image: null },
    { slot: "right", text: "", image: null },
  ])
  assert.equal(regionUsed(p, "footer"), true)
  assert.equal(regionUsed(p, "header"), false)

  const explicit = normalizePage({
    footer: { center: "{page} / {pages}" },
    numbering: { enabled: true, align: "center", format: "{page}" },
  })
  assert.equal(pageSlots(explicit, "footer")[1].text, "{page} / {pages}")
})

t("a slot carries a logo alongside its text", () => {
  const p = normalizePage({
    header: { left: { text: "Acme", image: { src: "/logo.png", height: 12, alt: "L" } } },
  })

  assert.deepEqual(p.header.left, { text: "Acme", image: { src: "/logo.png", alt: "L", height: 12 } })
  assert.equal(regionUsed(p, "header"), true)
  assert.equal(regionUsed(normalizePage({ footer: { right: { image: { src: "/l.png" } } } }), "footer"), true)
})

t("logo height defaults, converts units and clamps — as Tiptapex.Page does", () => {
  const height = (image) => normalizePage({ header: { left: { image } } }).header.left.image.height

  assert.equal(height({ src: "/l.png" }), 8)
  assert.equal(height({ src: "/l.png", height: "0.5in" }), 12.7)
  assert.equal(height({ src: "/l.png", height: 5000 }), 100)
  assert.equal(height({ src: "/l.png", height: 0 }), 8)
})

t("a logo src the server would reject is dropped here too", () => {
  for (const src of ["javascript:alert(1)", "data:text/html;base64,x", "data:image/png", "", null, 42]) {
    const slot = normalizePage({ header: { left: { text: "kept", image: { src } } } }).header.left
    assert.equal(slot.image, null, `expected ${JSON.stringify(src)} to be rejected`)
    assert.equal(slot.text, "kept")
  }

  // Image data URIs are the one `data:` shape allowed — Chrome needs them.
  const ok = normalizePage({ header: { left: { image: { src: "data:image/png;base64,iVBOR" } } } })
  assert.equal(ok.header.left.image.src, "data:image/png;base64,iVBOR")
})

t("runningKey changes when a header, footer or logo changes", () => {
  const base = normalizePage({ footer: { center: "a" } })
  assert.equal(runningKey(base), runningKey(normalizePage({ footer: { center: "a" } })))
  assert.notEqual(runningKey(base), runningKey(normalizePage({ footer: { center: "b" } })))
  assert.notEqual(
    runningKey(base),
    runningKey(normalizePage({ footer: { center: { text: "a", image: { src: "/l.png" } } } }))
  )
})

t("replaceTokens blanks unlisted tokens and leaves unknown braces", () => {
  assert.equal(replaceTokens("{title} {page}/{pages} {date}", { title: "R", page: "1", pages: "9" }), "R 1/9 ")
  assert.equal(replaceTokens("{nope} {page}", { page: "1" }), "{nope} 1")
})

t("resolvePageSetup never mutates the document it is given", () => {
  const shared = { type: "doc", content: [] }
  const out = resolvePageSetup(shared, { size: "a4" })
  assert.equal(shared.attrs, undefined, "the shared constant must stay untouched")
  assert.equal(out.doc.attrs.page.size, "a4")
  assert.equal(out.page.size, "a4")

  const off = resolvePageSetup({ type: "doc", attrs: { page: { size: "a4" } } }, false)
  assert.equal(off.doc.attrs.page, null)
  assert.equal(off.page, null)

  const kept = resolvePageSetup({ type: "doc", attrs: { page: { size: "legal" } } }, null)
  assert.equal(kept.page.size, "legal")
})
