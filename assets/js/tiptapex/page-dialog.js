// The "Page setup" dialog: whether the document is paginated at all, paper
// size, orientation, margins, header/footer slots — text and logos — and page
// numbering.
//
//   openPageDialog(editor, { labels, uploadImage })
//
// `uploadImage` is the hook's upload callback (`(file) => {url, filename}`);
// without it the logo fields still accept a pasted URL, the upload button
// just isn't shown.
//
// Applying writes the whole configuration onto the document
// (`editor.commands.setPageOptions`); unticking "Paginate this document" and
// applying clears it (`setPageOptions(null)`).
import { PAGE_PRESETS, DEFAULT_IMAGE_HEIGHT, defaultPage, normalizePage, pageDimensions } from "./page"

export const DEFAULT_PAGE_LABELS = {
  pageSetup: "Page setup",
  paginate: "Paginate this document",
  paperSize: "Paper size",
  orientation: "Orientation",
  portrait: "Portrait",
  landscape: "Landscape",
  width: "Width",
  height: "Height",
  margins: "Margins",
  marginTop: "Top",
  marginRight: "Right",
  marginBottom: "Bottom",
  marginLeft: "Left",
  header: "Header",
  footer: "Footer",
  slotLeft: "Left",
  slotCenter: "Center",
  slotRight: "Right",
  imageUrl: "Logo URL",
  imageHeight: "Logo height",
  uploadImage: "Upload image",
  removeImage: "Remove logo",
  uploadFailed: "The image could not be uploaded.",
  notAnImage: "That file is not an image.",
  numbering: "Page numbers",
  numberingEnabled: "Show page numbers",
  numberingRegion: "Place in",
  numberingAlign: "Alignment",
  numberingFormat: "Format",
  documentTitle: "Document title",
  tokensHint: "Available tokens: {page} {pages} {date} {time} {title}",
  htmlHint: "Basic HTML is allowed: <b> <i> <u> <span style=\"…\"> <h1>…<h6> <a> <img> <br>",
  millimetres: "mm",
  apply: "Apply",
  cancel: "Cancel",
  close: "Close",
  sizeLetter: "Letter",
  sizeLegal: "Legal",
  sizeTabloid: "Tabloid",
  sizeExecutive: "Executive",
  sizeA3: "A3",
  sizeA4: "A4",
  sizeA5: "A5",
  sizeCustom: "Custom",
}

const PRESET_ORDER = ["letter", "legal", "a4", "a5", "executive", "tabloid", "a3"]
const SLOTS = ["left", "center", "right"]

const el = (tag, className, props = {}) => Object.assign(document.createElement(tag), { className, ...props })

function field(labelText, control, className = "") {
  const wrap = el("label", `ttx-dialog-field ${className}`.trim())
  wrap.appendChild(el("span", "ttx-dialog-label", { textContent: labelText }))
  wrap.appendChild(control)
  return wrap
}

function section(title) {
  const s = el("section", "ttx-dialog-section")
  s.appendChild(el("h3", "ttx-dialog-heading", { textContent: title }))
  return s
}

function textInput(value, opts = {}) {
  const input = el("input", "ttx-dialog-input", { type: "text", value: value ?? "" })
  if (opts.placeholder) input.placeholder = opts.placeholder
  if (opts.title) input.title = opts.title
  return input
}

function numberInput(value, opts = {}) {
  return el("input", `ttx-dialog-input ttx-dialog-number ${opts.className || ""}`.trim(), {
    type: "number",
    min: opts.min ?? "0",
    step: opts.step ?? "0.1",
    value: String(round(value)),
    title: opts.title || "",
  })
}

function selectInput(options, value) {
  const select = el("select", "ttx-dialog-input")
  options.forEach(([optionValue, label]) => {
    select.appendChild(el("option", "", { value: optionValue, textContent: label }))
  })
  select.value = value
  return select
}

function checkbox(labelText, checked, className = "") {
  const input = el("input", "ttx-dialog-check", { type: "checkbox", checked })
  const label = el("label", `ttx-dialog-checkbox ${className}`.trim())
  label.appendChild(input)
  label.appendChild(el("span", "", { textContent: labelText }))
  return { input, label }
}

const round = (n) => Math.round(n * 100) / 100

// One slot's logo: a URL (typed or uploaded), a height in millimetres, and a
// way to clear it.
function imageControls(t, image, ctx) {
  const row = el("div", "ttx-dialog-image")
  let alt = image?.alt || ""

  const src = textInput(image?.src || "", { placeholder: t.imageUrl, title: t.imageUrl })
  src.classList.add("ttx-dialog-image-src")

  const height = numberInput(image?.height ?? DEFAULT_IMAGE_HEIGHT, {
    min: "1",
    step: "0.5",
    className: "ttx-dialog-image-height",
    title: `${t.imageHeight} (${t.millimetres})`,
  })

  const upload = el("button", "ttx-dialog-icon-btn", { type: "button", textContent: "↑", title: t.uploadImage })
  const clear = el("button", "ttx-dialog-icon-btn", { type: "button", textContent: "×", title: t.removeImage })

  const sync = () => {
    const has = src.value.trim() !== ""
    height.disabled = !has
    clear.disabled = !has
  }
  src.addEventListener("input", sync)

  if (ctx.uploadImage) {
    upload.addEventListener("click", async () => {
      const file = await ctx.pickFile("image/*")
      if (!file) return

      upload.disabled = true
      const original = upload.textContent
      upload.textContent = "…"

      try {
        const result = await ctx.uploadImage(file)
        if (result?.url) {
          src.value = result.url
          alt = result.filename || ""
          sync()
        }
      } catch (error) {
        console.error("[Tiptapex] logo upload failed:", error)
        window.alert(error?.ttxNotAnImage ? t.notAnImage : t.uploadFailed)
      } finally {
        upload.disabled = false
        upload.textContent = original
      }
    })
  } else {
    upload.style.display = "none"
  }

  clear.addEventListener("click", () => {
    src.value = ""
    alt = ""
    sync()
  })

  row.appendChild(src)
  row.appendChild(upload)
  row.appendChild(height)
  row.appendChild(clear)
  sync()

  return {
    row,
    value() {
      const value = src.value.trim()
      if (value === "") return null
      const parsed = parseFloat(height.value)
      return { src: value, alt, height: parsed > 0 ? parsed : DEFAULT_IMAGE_HEIGHT }
    },
  }
}

// A header/footer region: three slots, each with text and an optional logo.
function slotRow(t, region, ctx) {
  const row = el("div", "ttx-dialog-row ttx-dialog-row-3")
  const fields = {}

  SLOTS.forEach((slot) => {
    const cell = el("div", "ttx-dialog-field")
    cell.appendChild(el("span", "ttx-dialog-label", { textContent: t[`slot${slot[0].toUpperCase()}${slot.slice(1)}`] }))

    const text = textInput(region[slot].text)
    const image = imageControls(t, region[slot].image, ctx)

    cell.appendChild(text)
    cell.appendChild(image.row)
    row.appendChild(cell)

    fields[slot] = { text, image }
  })

  const value = () =>
    Object.fromEntries(SLOTS.map((slot) => [slot, { text: fields[slot].text.value, image: fields[slot].image.value() }]))

  return { row, value }
}

export function openPageDialog(editor, opts = {}) {
  const t = { ...DEFAULT_PAGE_LABELS, ...(opts.labels || {}) }
  const stored = normalizePage(editor.state.doc.attrs?.page)
  const current = stored || defaultPage()

  // File inputs outlive a cancelled picker (no event fires), so they are
  // tracked and swept up when the dialog closes.
  const pickers = []
  const ctx = {
    uploadImage: opts.uploadImage,
    pickFile: (accept) =>
      new Promise((resolve) => {
        const input = el("input", "", { type: "file", accept })
        input.style.display = "none"
        document.body.appendChild(input)
        pickers.push(input)

        const done = (file) => {
          input.remove()
          resolve(file)
        }
        input.addEventListener("change", () => done(input.files?.[0] || null))
        input.addEventListener("cancel", () => done(null))
        input.click()
      }),
  }

  const backdrop = el("div", "ttx-dialog-backdrop")
  const dialog = el("div", "ttx-dialog")
  dialog.setAttribute("role", "dialog")
  dialog.setAttribute("aria-modal", "true")
  dialog.setAttribute("aria-label", t.pageSetup)

  const header = el("div", "ttx-dialog-header")
  header.appendChild(el("h2", "ttx-dialog-title", { textContent: t.pageSetup }))
  const closeBtn = el("button", "ttx-dialog-close", { type: "button", textContent: "×", title: t.close })
  closeBtn.setAttribute("aria-label", t.close)
  header.appendChild(closeBtn)

  const body = el("div", "ttx-dialog-body")

  // ---- On/off -----------------------------------------------------
  // The single control that decides whether this document is paginated.
  // Everything below stays editable while it is off, so you can set the
  // paper up first and switch it on with one tick.
  const paginate = checkbox(t.paginate, stored != null, "ttx-dialog-toggle")
  const syncPaginate = () => body.classList.toggle("is-off", !paginate.input.checked)
  paginate.input.addEventListener("change", syncPaginate)
  body.appendChild(paginate.label)

  // ---- Paper ------------------------------------------------------
  const paper = section(t.paperSize)
  const presetOptions = PRESET_ORDER.filter((name) => PAGE_PRESETS[name]).map((name) => [
    name,
    t[`size${name.charAt(0).toUpperCase()}${name.slice(1)}`] || name.toUpperCase(),
  ])
  presetOptions.push(["custom", t.sizeCustom])

  const sizeSelect = selectInput(presetOptions, typeof current.size === "string" ? current.size : "custom")
  const orientationSelect = selectInput(
    [
      ["portrait", t.portrait],
      ["landscape", t.landscape],
    ],
    current.orientation
  )

  const paperRow = el("div", "ttx-dialog-row ttx-dialog-row-2")
  paperRow.appendChild(field(t.paperSize, sizeSelect))
  paperRow.appendChild(field(t.orientation, orientationSelect))
  paper.appendChild(paperRow)

  // Custom size inputs are seeded with the current paper so switching to
  // "Custom" starts from what you already see.
  const seed = pageDimensions({ ...current, orientation: "portrait" })
  const widthInput = numberInput(seed.width)
  const heightInput = numberInput(seed.height)
  const customRow = el("div", "ttx-dialog-row ttx-dialog-row-2")
  customRow.appendChild(field(`${t.width} (${t.millimetres})`, widthInput))
  customRow.appendChild(field(`${t.height} (${t.millimetres})`, heightInput))
  paper.appendChild(customRow)

  const syncCustom = () => {
    customRow.style.display = sizeSelect.value === "custom" ? "" : "none"
  }
  sizeSelect.addEventListener("change", syncCustom)
  syncCustom()

  body.appendChild(paper)

  // ---- Margins ----------------------------------------------------
  const margins = section(`${t.margins} (${t.millimetres})`)
  const marginRow = el("div", "ttx-dialog-row ttx-dialog-row-4")
  const marginInputs = {}
  ;[
    ["top", t.marginTop],
    ["right", t.marginRight],
    ["bottom", t.marginBottom],
    ["left", t.marginLeft],
  ].forEach(([side, label]) => {
    marginInputs[side] = numberInput(current.margins[side])
    marginRow.appendChild(field(label, marginInputs[side]))
  })
  margins.appendChild(marginRow)
  body.appendChild(margins)

  // ---- Header / footer --------------------------------------------
  const headerSection = section(t.header)
  const headerSlots = slotRow(t, current.header, ctx)
  headerSection.appendChild(headerSlots.row)
  body.appendChild(headerSection)

  const footerSection = section(t.footer)
  const footerSlots = slotRow(t, current.footer, ctx)
  footerSection.appendChild(footerSlots.row)
  footerSection.appendChild(el("p", "ttx-dialog-hint", { textContent: t.tokensHint }))
  footerSection.appendChild(el("p", "ttx-dialog-hint", { textContent: t.htmlHint }))
  body.appendChild(footerSection)

  // ---- Numbering ---------------------------------------------------
  const numbering = section(t.numbering)
  const numberingOn = checkbox(t.numberingEnabled, current.numbering.enabled)
  numbering.appendChild(numberingOn.label)

  const regionSelect = selectInput(
    [
      ["header", t.header],
      ["footer", t.footer],
    ],
    current.numbering.region
  )
  const alignSelect = selectInput(
    [
      ["left", t.slotLeft],
      ["center", t.slotCenter],
      ["right", t.slotRight],
    ],
    current.numbering.align
  )
  const formatInput = textInput(current.numbering.format, { placeholder: "{page}" })

  const numberingRow = el("div", "ttx-dialog-row ttx-dialog-row-3")
  numberingRow.appendChild(field(t.numberingRegion, regionSelect))
  numberingRow.appendChild(field(t.numberingAlign, alignSelect))
  numberingRow.appendChild(field(t.numberingFormat, formatInput))
  numbering.appendChild(numberingRow)

  const syncNumbering = () => {
    numberingRow.classList.toggle("is-disabled", !numberingOn.input.checked)
    ;[regionSelect, alignSelect, formatInput].forEach((input) => {
      input.disabled = !numberingOn.input.checked
    })
  }
  numberingOn.input.addEventListener("change", syncNumbering)
  syncNumbering()

  const titleInput = textInput(current.title || "")
  numbering.appendChild(field(t.documentTitle, titleInput, "ttx-dialog-field-wide"))
  body.appendChild(numbering)

  syncPaginate()

  // ---- Footer ------------------------------------------------------
  const actions = el("div", "ttx-dialog-actions")
  const cancelBtn = el("button", "ttx-dialog-btn", { type: "button", textContent: t.cancel })
  const applyBtn = el("button", "ttx-dialog-btn ttx-dialog-btn-primary", { type: "button", textContent: t.apply })
  actions.appendChild(el("div", "ttx-dialog-spacer"))
  actions.appendChild(cancelBtn)
  actions.appendChild(applyBtn)

  dialog.appendChild(header)
  dialog.appendChild(body)
  dialog.appendChild(actions)
  backdrop.appendChild(dialog)
  document.body.appendChild(backdrop)

  const close = () => {
    document.removeEventListener("keydown", onKeydown, true)
    pickers.forEach((input) => input.remove())
    backdrop.remove()
    editor.commands.focus()
  }

  const onKeydown = (event) => {
    if (event.key === "Escape") {
      event.stopPropagation()
      close()
    }
  }
  document.addEventListener("keydown", onKeydown, true)

  backdrop.addEventListener("mousedown", (event) => {
    if (event.target === backdrop) close()
  })

  closeBtn.addEventListener("click", close)
  cancelBtn.addEventListener("click", close)

  applyBtn.addEventListener("click", () => {
    if (!paginate.input.checked) {
      editor.commands.setPageOptions(null)
      close()
      return
    }

    const number = (input, fallback) => {
      const value = parseFloat(input.value)
      return Number.isFinite(value) && value >= 0 ? value : fallback
    }

    editor.commands.setPageOptions({
      size:
        sizeSelect.value === "custom"
          ? { width: number(widthInput, seed.width), height: number(heightInput, seed.height) }
          : sizeSelect.value,
      orientation: orientationSelect.value,
      margins: {
        top: number(marginInputs.top, current.margins.top),
        right: number(marginInputs.right, current.margins.right),
        bottom: number(marginInputs.bottom, current.margins.bottom),
        left: number(marginInputs.left, current.margins.left),
      },
      header: headerSlots.value(),
      footer: footerSlots.value(),
      numbering: {
        enabled: numberingOn.input.checked,
        region: regionSelect.value,
        align: alignSelect.value,
        format: formatInput.value || "{page}",
      },
      title: titleInput.value || null,
    })

    close()
  })

  sizeSelect.focus()
  return { close }
}
