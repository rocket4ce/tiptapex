// Integration checks against a real Tiptap editor in jsdom.
//
// jsdom has no layout — every element measures 0×0 — so this cannot verify
// where the page breaks land (see pagination_test.mjs for that maths). What
// it does verify is the wiring that only a real editor can prove: that the
// page setup survives as a `doc` node attribute through getJSON/setContent,
// that `setDocAttribute` is actually available in the installed ProseMirror,
// that the page-break node round-trips through HTML, and that the pagination
// plugin mounts and tears down without throwing.
import assert from "node:assert/strict"

import { dom } from "./dom.mjs"
import { test } from "./harness.mjs"

const { Editor } = await import("@tiptap/core")
const { buildExtensions, openPageDialog } = await import("tiptapex")
const { normalizePage } = await import("tiptapex/page")

const PAGE = {
  size: "legal",
  orientation: "landscape",
  margins: { top: 10, right: 10, bottom: 10, left: 10 },
  footer: { left: "", center: "{page} / {pages}", right: "" },
  numbering: { enabled: true, region: "footer", align: "center", format: "{page}" },
}

const paragraph = (text) => ({ type: "paragraph", content: [{ type: "text", text }] })

function editor(doc, opts = {}) {
  const element = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(element)

  const instance = new Editor({
    element,
    content: doc,
    extensions: buildExtensions({ dragHandle: false, ...opts }),
  })

  instance.tiptapexTestElement = element
  return instance
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 30))
const stackOf = (e) => e.tiptapexTestElement.querySelector(".ttx-page-stack")

const t = (name, fn) => test("editor (jsdom)", name, fn)

t("a page setup on the doc node survives getJSON", () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("hi")] })
  try {
    const json = e.getJSON()
    assert.equal(json.attrs.page.size, "legal")
    assert.equal(json.attrs.page.orientation, "landscape")
    assert.equal(json.attrs.page.numbering.enabled, true)
    assert.equal(json.content[0].content[0].text, "hi")
  } finally {
    e.destroy()
  }
})

t("a document with no page setup stays unpaginated", () => {
  const e = editor({ type: "doc", content: [paragraph("hi")] })
  try {
    assert.equal(normalizePage(e.state.doc.attrs.page), null)
  } finally {
    e.destroy()
  }
})

t("defaultPage seeds documents that carry none — the collaboration path", () => {
  const e = editor({ type: "doc", content: [paragraph("hi")] }, { defaultPage: PAGE })
  try {
    assert.equal(e.state.doc.attrs.page.size, "legal")
    assert.equal(e.getJSON().attrs.page.size, "legal")
  } finally {
    e.destroy()
  }
})

t("an explicit null in the document beats the seeded default", () => {
  const e = editor({ type: "doc", attrs: { page: null }, content: [paragraph("hi")] }, { defaultPage: PAGE })
  try {
    assert.equal(e.state.doc.attrs.page, null)
  } finally {
    e.destroy()
  }
})

t("setPageOptions merges a patch and is undoable", () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("hi")] })
  try {
    assert.equal(e.commands.setPageOptions({ size: "a4" }), true, "setDocAttribute must exist")
    assert.equal(e.state.doc.attrs.page.size, "a4")
    assert.equal(e.state.doc.attrs.page.orientation, "landscape", "untouched keys survive")

    e.commands.undo()
    assert.equal(e.state.doc.attrs.page.size, "legal")
  } finally {
    e.destroy()
  }
})

t("setPageOptions(null) turns page layout off", () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("hi")] })
  try {
    e.commands.setPageOptions(null)
    assert.equal(e.state.doc.attrs.page, null)
    assert.equal(e.getJSON().attrs.page, null)
  } finally {
    e.destroy()
  }
})

t("setPageOptions normalises what it is given", () => {
  const e = editor({ type: "doc", content: [paragraph("hi")] })
  try {
    e.commands.setPageOptions({ size: "papyrus", margins: { top: "1in" } })
    assert.equal(e.state.doc.attrs.page.size, "letter")
    assert.equal(e.state.doc.attrs.page.margins.top, 25.4)
  } finally {
    e.destroy()
  }
})

t("a page break is a real block node and round-trips through HTML", () => {
  const e = editor({ type: "doc", content: [paragraph("a"), paragraph("b")] })
  try {
    e.commands.setPageBreak()
    const types = e.getJSON().content.map((node) => node.type)
    assert.ok(types.includes("pageBreak"), `expected a pageBreak in ${types.join(", ")}`)

    const html = e.getHTML()
    assert.ok(html.includes('data-page-break="true"'), html)

    // The HTML source view parses edits back with the editor's own schema —
    // the break must survive that trip.
    e.commands.setContent(html)
    assert.ok(e.getJSON().content.some((node) => node.type === "pageBreak"))
  } finally {
    e.destroy()
  }
})

t("the pagination plugin mounts, measures and tears down without throwing", async () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("a"), paragraph("b")] })
  try {
    await tick()
    assert.equal(typeof e.storage.tiptapexPagination.pages, "number")
    assert.ok(stackOf(e), "the sheet is mounted")
    e.commands.insertContent(paragraph("c"))
    await tick()
  } finally {
    e.destroy()
  }
})

t("enough content to overflow actually renders the sheet break", async () => {
  // Letter portrait, 10mm margins -> ~1000px of content box, 300px blocks.
  const content = Array.from({ length: 8 }, (_, i) => paragraph(`block ${i}`))
  const e = editor({ type: "doc", attrs: { page: { ...PAGE, orientation: "portrait" } }, content })
  try {
    await tick()
    const gaps = e.tiptapexTestElement.querySelectorAll(".ttx-page-gap")
    assert.ok(gaps.length >= 1, `expected page gaps, got ${gaps.length}`)
    assert.ok(e.storage.tiptapexPagination.pages > 1)

    // The running footer must render inside the gap, tokens resolved.
    const footer = gaps[0].querySelector(".ttx-page-runner-footer .ttx-page-slot.is-center")
    assert.ok(footer, "the gap carries a running footer")
    assert.match(footer.textContent, /^\d+ \/ \d+$/, `got ${JSON.stringify(footer.textContent)}`)
  } finally {
    e.destroy()
  }
})

t("a logo renders as an <img> in the running header", async () => {
  const page = {
    ...PAGE,
    orientation: "portrait",
    header: { left: { text: "Acme", image: { src: "/logo.png", height: 12, alt: "Logo" } } },
  }
  const content = Array.from({ length: 8 }, (_, i) => paragraph(`block ${i}`))
  const e = editor({ type: "doc", attrs: { page }, content })

  try {
    await tick()
    const cell = e.tiptapexTestElement.querySelector(".ttx-page-head .ttx-page-slot.is-left")
    const img = cell.querySelector("img")

    assert.ok(img, "the running header draws the logo")
    assert.ok(img.getAttribute("src").endsWith("/logo.png"))
    assert.equal(img.alt, "Logo")
    assert.ok(Math.abs(parseFloat(img.style.height) - 45.354) < 0.01, "12mm at 96dpi")
    assert.equal(cell.querySelector("span").textContent, "Acme", "text still renders beside it")

    // The gap between sheets carries the next page's header, logo included.
    const gapHeader = e.tiptapexTestElement.querySelector(".ttx-page-gap .ttx-page-runner-header img")
    assert.ok(gapHeader, "and so does every following page")
  } finally {
    e.destroy()
  }
})

t("changing only the header re-renders the gaps", async () => {
  const content = Array.from({ length: 8 }, (_, i) => paragraph(`block ${i}`))
  const e = editor({
    type: "doc",
    attrs: { page: { ...PAGE, orientation: "portrait" } },
    content,
  })

  try {
    await tick()
    const slot = () =>
      e.tiptapexTestElement.querySelector(".ttx-page-gap .ttx-page-runner-header .ttx-page-slot.is-left")
    assert.equal(slot().textContent, "")

    // Geometry is unchanged, so only the running-config key can trigger this.
    e.commands.setPageOptions({ header: { left: "Confidential" } })
    await tick()
    assert.equal(slot().textContent, "Confidential")
  } finally {
    e.destroy()
  }
})

t("a forced break renders a removable chip that deletes the node", async () => {
  const e = editor({
    type: "doc",
    attrs: { page: PAGE },
    content: [paragraph("a"), { type: "pageBreak" }, paragraph("b")],
  })
  try {
    await tick()
    const chip = e.tiptapexTestElement.querySelector(".ttx-page-break-chip")
    assert.ok(chip, "the gutter carries a chip for the forced break")

    chip.dispatchEvent(new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true }))
    assert.ok(
      !e.getJSON().content.some((node) => node.type === "pageBreak"),
      "clicking the chip removes the break"
    )
  } finally {
    e.destroy()
  }
})

t("turning page layout off and back on re-mounts the sheet", async () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("a")] })
  try {
    await tick()
    assert.ok(stackOf(e), "mounted to begin with")

    e.commands.setPageOptions(null)
    await tick()
    assert.equal(e.state.doc.attrs.page, null)
    assert.equal(stackOf(e), null, "the sheet is torn down")

    e.commands.setPageOptions({ size: "a4" })
    await tick()
    assert.equal(e.state.doc.attrs.page?.size, "a4", "the setup comes back")
    assert.ok(stackOf(e), "and so does the sheet")
  } finally {
    e.destroy()
  }
})

// The dialog's on/off state is a single visible checkbox, so turning page
// layout off is always reversible from the same place.
const toggle = () => document.querySelector(".ttx-dialog-toggle .ttx-dialog-check")
const apply = () => document.querySelector(".ttx-dialog-btn-primary").click()

t("the dialog reflects whether the document is paginated", () => {
  const off = editor({ type: "doc", content: [paragraph("a")] })
  try {
    const dialog = openPageDialog(off)
    assert.equal(toggle().checked, false, "an unpaginated document shows the box unticked")
    dialog.close()
  } finally {
    off.destroy()
  }

  const on = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("a")] })
  try {
    const dialog = openPageDialog(on)
    assert.equal(toggle().checked, true)
    dialog.close()
  } finally {
    on.destroy()
  }
})

t("ticking the box and applying turns page layout on", () => {
  const e = editor({ type: "doc", content: [paragraph("a")] })
  try {
    openPageDialog(e)
    toggle().checked = true
    apply()

    assert.notEqual(e.state.doc.attrs.page, null, "Apply must set a page setup")
    assert.equal(e.state.doc.attrs.page.size, "letter")
  } finally {
    e.destroy()
  }
})

t("unticking turns it off, and it can always be turned back on", () => {
  const e = editor({ type: "doc", attrs: { page: PAGE }, content: [paragraph("a")] })
  try {
    openPageDialog(e)
    toggle().checked = false
    apply()
    assert.equal(e.state.doc.attrs.page, null, "unticking clears the page setup")

    openPageDialog(e)
    assert.equal(toggle().checked, false, "and the dialog says so")
    toggle().checked = true
    apply()
    assert.notEqual(e.state.doc.attrs.page, null, "ticking brings pages back")
  } finally {
    e.destroy()
  }
})

t("the dialog round-trips a logo, and Apply keeps it", () => {
  const page = { ...PAGE, header: { left: { text: "Acme", image: { src: "/logo.png", height: 12 } } } }
  const e = editor({ type: "doc", attrs: { page }, content: [paragraph("a")] })
  try {
    openPageDialog(e)
    const src = document.querySelector(".ttx-dialog-image-src")
    assert.equal(src.value, "/logo.png", "the stored logo is shown")

    apply()
    assert.deepEqual(e.state.doc.attrs.page.header.left.image, {
      src: "/logo.png",
      alt: "",
      height: 12,
    })
  } finally {
    e.destroy()
  }
})

t("page: false leaves the page extensions out entirely", () => {
  const e = editor({ type: "doc", content: [paragraph("hi")] }, { page: false })
  try {
    assert.equal(typeof e.commands.setPageOptions, "undefined")
    assert.equal(typeof e.commands.setPageBreak, "undefined")
    assert.equal(e.state.doc.attrs.page, undefined)
  } finally {
    e.destroy()
  }
})
