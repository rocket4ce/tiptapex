// Toolbar for the Tiptapex editor. Built as a small DOM helper so the hook
// can call `buildToolbar(editor, rootEl, config)`.
//
// Buttons are grouped (with thin dividers) and use Heroicons-style SVG icons.
// Colour palettes are popovers anchored to a trigger.
//
// The toolbar is fully config-driven:
//
//   buildToolbar(editor, root, {
//     groups: ["marks", "blocks", "align", "lists", "typography",
//              "colors", "insert", "utilities", "history"],   // ordered subset
//     labels: { bold: "Negrita", ... },                       // i18n overrides
//     textSizes, textColors, highlights, fontFamilies, lineHeights,
//     uploadFiles: (files) => Promise,   // provided by the hook; omit to hide
//                                        // the upload buttons
//     custom: [{ icon: () => Node, title, run, activeWhen }], // extra buttons
//   })

export const DEFAULT_TEXT_SIZES = ["12px", "14px", "16px", "18px", "20px", "24px", "32px"]
export const DEFAULT_TEXT_COLORS = ["#111111", "#374151", "#6b7280", "#dc2626", "#ea580c", "#f59e0b", "#16a34a", "#0891b2", "#2563eb", "#7c3aed", "#db2777"]
export const DEFAULT_HIGHLIGHTS = ["#fef3c7", "#dcfce7", "#dbeafe", "#fae8ff", "#fee2e2", "#fed7aa", "#cffafe"]
export const DEFAULT_FONT_FAMILIES = [
  { value: "Inter, ui-sans-serif, system-ui, sans-serif", label: "Sans" },
  { value: "Georgia, serif", label: "Serif" },
  { value: "Menlo, Monaco, monospace", label: "Mono" },
]
export const DEFAULT_LINE_HEIGHTS = ["1", "1.15", "1.5", "2"]

export const DEFAULT_GROUPS = [
  "marks",
  "blocks",
  "align",
  "lists",
  "typography",
  "colors",
  "insert",
  "utilities",
  "history",
]

export const DEFAULT_LABELS = {
  bold: "Bold (Cmd/Ctrl+B)",
  italic: "Italic (Cmd/Ctrl+I)",
  strike: "Strikethrough",
  code: "Inline code",
  blockStyle: "Style",
  paragraph: "Paragraph",
  heading1: "Heading 1",
  heading2: "Heading 2",
  heading3: "Heading 3",
  quote: "Quote",
  codeBlock: "Code block",
  alignLeft: "Align left",
  alignCenter: "Center",
  alignRight: "Align right",
  alignJustify: "Justify",
  bulletList: "Bullet list",
  orderedList: "Numbered list",
  taskList: "Task list",
  fontFamily: "Font",
  fontSize: "Size",
  lineHeight: "Line height",
  textColor: "Text color",
  backgroundColor: "Background color",
  clear: "Remove",
  insertLink: "Insert link",
  linkPrompt: "Link URL:",
  uploadImage: "Upload image",
  uploadFile: "Upload file (PDF, doc…)",
  uploadVideo: "Upload video (.mp4, .webm)",
  youtube: "Embed YouTube video",
  youtubePrompt: "YouTube video URL:",
  insertTable: "Insert table",
  horizontalRule: "Horizontal rule",
  invisibleChars: "Show invisible characters",
  undo: "Undo (Cmd/Ctrl+Z)",
  redo: "Redo (Cmd/Ctrl+Shift+Z)",
}

// SVG icon helper — uses Heroicons mini paths inline.
const svgNS = "http://www.w3.org/2000/svg"

const icon = (paths, opts = {}) => {
  const s = document.createElementNS(svgNS, "svg")
  s.setAttribute("viewBox", "0 0 20 20")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", opts.weight || "1.6")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.setAttribute("aria-hidden", "true")
  paths.forEach((d) => {
    const p = document.createElementNS(svgNS, "path")
    p.setAttribute("d", d)
    s.appendChild(p)
  })
  return s
}

export const ICONS = {
  bold: () => textGlyph("B", { weight: 800 }),
  italic: () => textGlyph("I", { italic: true, weight: 600 }),
  underline: () => textGlyph("U", { underline: true, weight: 600 }),
  strike: () => textGlyph("S", { strike: true, weight: 600 }),
  code: () => icon(["M7 6L3 10L7 14", "M13 6L17 10L13 14"]),
  alignLeft: () => icon(["M3 5h14", "M3 9h10", "M3 13h14", "M3 17h7"]),
  alignCenter: () => icon(["M3 5h14", "M5 9h10", "M3 13h14", "M6 17h8"]),
  alignRight: () => icon(["M3 5h14", "M7 9h10", "M3 13h14", "M10 17h7"]),
  alignJustify: () => icon(["M3 5h14", "M3 9h14", "M3 13h14", "M3 17h14"]),
  bullet: () => icon(["M3 5.5h.01", "M3 10h.01", "M3 14.5h.01", "M7 5.5h10", "M7 10h10", "M7 14.5h10"]),
  ordered: () => icon(["M3 4v2.5", "M3 5l.5-.5", "M3 9.5h1.5L3 11.5h1.5", "M3 14h1.5", "M3 15.5h1.5L3 17h1.5", "M7 5.5h10", "M7 10h10", "M7 14.5h10"]),
  task: () => icon(["M4 4h12v12H4z", "M7 10l2 2 4-4"]),
  link: () => icon(["M9 11a3 3 0 0 0 4.24 0l2.83-2.83a3 3 0 1 0-4.24-4.24l-1.4 1.41", "M11 9a3 3 0 0 0-4.24 0l-2.83 2.83a3 3 0 1 0 4.24 4.24l1.4-1.41"]),
  image: () => icon(["M3 4h14v12H3z", "M3 13l4-4 3 3 3-3 4 4", "M13 7a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4z"]),
  table: () => icon(["M3 4h14v12H3z", "M3 9h14", "M3 13h14", "M9 4v12", "M13 4v12"]),
  // Pilcrow (¶) — the universally recognised glyph for "show formatting marks"
  // / "invisible characters". Rendered as a glyph instead of strokes so it's
  // clear at 16px.
  invisible: () => textGlyph("¶", { weight: 700 }),
  undo: () => icon(["M8 6L4 10l4 4", "M4 10h8a4 4 0 0 1 0 8h-2"]),
  redo: () => icon(["M12 6l4 4-4 4", "M16 10H8a4 4 0 0 0 0 8h2"]),
  blockquote: () => icon(["M6 8c-1.5 0-2.5 1-2.5 2.5S4.5 13 6 13h1v2c-2 0-3.5-1.5-3.5-3.5S5 8 6 8z M14 8c-1.5 0-2.5 1-2.5 2.5S12.5 13 14 13h1v2c-2 0-3.5-1.5-3.5-3.5S13 8 14 8z"]),
  hr: () => icon(["M3 10h14"]),
  caret: () => icon(["M5 8l5 4 5-4"]),
  // Document with an upward arrow — the universal upload metaphor.
  drop: () =>
    icon([
      "M6 3h6l3 3v11H6z",
      "M12 3v3h3",
      "M10 14V9",
      "M8 11l2-2 2 2",
    ]),
  // Generic video / film icon
  video: () =>
    icon([
      "M3 6h10v8H3z",
      "M13 8l4-2v8l-4-2",
    ]),
  // YouTube-style play button inside a rounded rect
  youtube: () =>
    icon(
      [
        "M3 6c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2v8c0 1.1-.9 2-2 2H5c-1.1 0-2-.9-2-2V6z",
        "M9 7.5v5l4-2.5z",
      ],
      { weight: "1.5" }
    ),
}

const textGlyph = (txt, opts = {}) => {
  const span = document.createElement("span")
  span.textContent = txt
  span.style.fontFamily = "ui-serif, Georgia, serif"
  span.style.fontWeight = opts.weight || 600
  if (opts.italic) span.style.fontStyle = "italic"
  if (opts.underline) span.style.textDecoration = "underline"
  if (opts.strike) span.style.textDecoration = "line-through"
  return span
}

function btn(content, opts = {}) {
  const b = document.createElement("button")
  b.type = "button"
  b.className = "ttx-tb-btn"
  if (opts.title) b.title = opts.title
  if (opts.title) b.setAttribute("aria-label", opts.title)
  if (content instanceof Node) b.appendChild(content)
  else b.textContent = content

  b.addEventListener("mousedown", (e) => {
    e.preventDefault()
    opts.run?.(e)
  })

  if (opts.editor && opts.activeWhen) {
    const sync = () => b.classList.toggle("is-active", !!opts.activeWhen())
    opts.editor.on("selectionUpdate", sync)
    opts.editor.on("update", sync)
    sync()
  }
  return b
}

function group(children) {
  const g = document.createElement("div")
  g.className = "ttx-tb-group"
  children.filter(Boolean).forEach((c) => g.appendChild(c))
  return g
}

function selectField(label, options, onChange) {
  const wrap = document.createElement("label")
  wrap.className = "ttx-tb-select"
  const sel = document.createElement("select")
  sel.title = label
  sel.setAttribute("aria-label", label)
  sel.addEventListener("mousedown", (e) => e.stopPropagation())
  sel.addEventListener("change", (e) => onChange(e.target.value))
  const placeholder = document.createElement("option")
  placeholder.disabled = true
  placeholder.selected = true
  placeholder.textContent = label
  sel.appendChild(placeholder)
  options.forEach((opt) => {
    const o = document.createElement("option")
    o.value = typeof opt === "string" ? opt : opt.value
    o.textContent = typeof opt === "string" ? opt : opt.label
    sel.appendChild(o)
  })
  wrap.appendChild(sel)
  return wrap
}

function paletteButton({ title, clearTitle, defaultColor, colors, onPick, onClear }) {
  const wrap = document.createElement("div")
  wrap.className = "ttx-tb-palette"

  const trigger = document.createElement("button")
  trigger.type = "button"
  trigger.className = "ttx-tb-btn-trigger"
  trigger.title = title
  trigger.setAttribute("aria-label", title)

  const dot = document.createElement("span")
  dot.className = "ttx-tb-color-dot"
  dot.style.backgroundColor = defaultColor
  trigger.appendChild(dot)
  trigger.appendChild(ICONS.caret())

  const popover = document.createElement("div")
  popover.className = "ttx-tb-popover"

  colors.forEach((c) => {
    const sw = document.createElement("button")
    sw.type = "button"
    sw.className = "ttx-tb-swatch"
    sw.style.backgroundColor = c
    sw.title = c
    sw.addEventListener("mousedown", (e) => {
      e.preventDefault()
      onPick(c)
      wrap.classList.remove("is-open")
    })
    popover.appendChild(sw)
  })
  if (onClear) {
    const clear = document.createElement("button")
    clear.type = "button"
    clear.className = "ttx-tb-swatch is-clear"
    clear.textContent = "×"
    clear.title = clearTitle || "Remove"
    clear.addEventListener("mousedown", (e) => {
      e.preventDefault()
      onClear()
      wrap.classList.remove("is-open")
    })
    popover.appendChild(clear)
  }

  trigger.addEventListener("mousedown", (e) => {
    e.preventDefault()
    e.stopPropagation()
    wrap.classList.toggle("is-open")
  })

  // close on outside click
  document.addEventListener("mousedown", (e) => {
    if (!wrap.contains(e.target)) wrap.classList.remove("is-open")
  })

  wrap.appendChild(trigger)
  wrap.appendChild(popover)
  return wrap
}

// A toolbar button that opens the OS file picker and hands the selection to
// the hook-provided `uploadFiles` callback (which POSTs and inserts).
function uploadButton({ title, accept, icon: iconNode, uploadFiles }) {
  const input = document.createElement("input")
  input.type = "file"
  input.accept = accept
  input.style.display = "none"
  document.body.appendChild(input)

  input.addEventListener("change", async () => {
    const file = input.files?.[0]
    input.value = ""
    if (!file) return
    try {
      await uploadFiles([file], null)
    } catch (e) {
      console.error("[Tiptapex] upload failed:", e)
    }
  })

  return btn(iconNode, {
    title,
    run: () => input.click(),
  })
}

// ---------------------------------------------------------------------------
// Group registry — each entry builds one toolbar group. `config.groups`
// selects an ordered subset; hosts can append extra buttons via
// `config.custom`.
// ---------------------------------------------------------------------------

const GROUPS = {
  marks(editor, t) {
    return group([
      btn(ICONS.bold(), { title: t.bold, editor, run: () => editor.chain().focus().toggleBold().run(), activeWhen: () => editor.isActive("bold") }),
      btn(ICONS.italic(), { title: t.italic, editor, run: () => editor.chain().focus().toggleItalic().run(), activeWhen: () => editor.isActive("italic") }),
      btn(ICONS.strike(), { title: t.strike, editor, run: () => editor.chain().focus().toggleStrike().run(), activeWhen: () => editor.isActive("strike") }),
      btn(ICONS.code(), { title: t.code, editor, run: () => editor.chain().focus().toggleCode().run(), activeWhen: () => editor.isActive("code") }),
    ])
  },

  blocks(editor, t) {
    return group([
      selectField(
        t.blockStyle,
        [
          { value: "p", label: t.paragraph },
          { value: "h1", label: t.heading1 },
          { value: "h2", label: t.heading2 },
          { value: "h3", label: t.heading3 },
          { value: "quote", label: t.quote },
          { value: "code", label: t.codeBlock },
        ],
        (v) => {
          const chain = editor.chain().focus()
          if (v === "p") chain.setParagraph().run()
          else if (v.startsWith("h")) chain.toggleHeading({ level: parseInt(v.slice(1), 10) }).run()
          else if (v === "quote") chain.toggleBlockquote().run()
          else if (v === "code") chain.toggleCodeBlock().run()
        }
      ),
    ])
  },

  align(editor, t) {
    const alignments = [
      ["left", ICONS.alignLeft(), t.alignLeft],
      ["center", ICONS.alignCenter(), t.alignCenter],
      ["right", ICONS.alignRight(), t.alignRight],
      ["justify", ICONS.alignJustify(), t.alignJustify],
    ]
    return group(
      alignments.map(([al, ic, label]) =>
        btn(ic, {
          title: label,
          editor,
          run: () => editor.chain().focus().setTextAlign(al).run(),
          activeWhen: () => editor.isActive({ textAlign: al }),
        })
      )
    )
  },

  lists(editor, t) {
    return group([
      btn(ICONS.bullet(), { title: t.bulletList, editor, run: () => editor.chain().focus().toggleBulletList().run(), activeWhen: () => editor.isActive("bulletList") }),
      btn(ICONS.ordered(), { title: t.orderedList, editor, run: () => editor.chain().focus().toggleOrderedList().run(), activeWhen: () => editor.isActive("orderedList") }),
      btn(ICONS.task(), { title: t.taskList, editor, run: () => editor.chain().focus().toggleTaskList().run(), activeWhen: () => editor.isActive("taskList") }),
    ])
  },

  typography(editor, t, config) {
    return group([
      selectField(t.fontFamily, config.fontFamilies, (v) => editor.chain().focus().setFontFamily(v).run()),
      selectField(t.fontSize, config.textSizes, (v) => editor.commands.setFontSize(v)),
      selectField(t.lineHeight, config.lineHeights, (v) => editor.commands.setLineHeight(v)),
    ])
  },

  colors(editor, t, config) {
    return group([
      paletteButton({
        title: t.textColor,
        clearTitle: t.clear,
        defaultColor: config.textColors[0],
        colors: config.textColors,
        onPick: (c) => editor.chain().focus().setColor(c).run(),
        onClear: () => editor.chain().focus().unsetColor().run(),
      }),
      paletteButton({
        title: t.backgroundColor,
        clearTitle: t.clear,
        defaultColor: config.highlights[0],
        colors: config.highlights,
        onPick: (c) => editor.commands.setBackgroundColor(c),
        onClear: () => editor.commands.unsetBackgroundColor(),
      }),
    ])
  },

  insert(editor, t, config) {
    const canUpload = typeof config.uploadFiles === "function"
    return group([
      btn(ICONS.link(), {
        title: t.insertLink,
        editor,
        run: () => {
          const previous = editor.getAttributes("link").href || ""
          const url = window.prompt(t.linkPrompt, previous)
          if (url === null) return
          if (url === "") return editor.chain().focus().unsetLink().run()
          editor.chain().focus().setLink({ href: url }).run()
        },
        activeWhen: () => editor.isActive("link"),
      }),
      canUpload &&
        uploadButton({
          title: t.uploadImage,
          accept: "image/*",
          icon: ICONS.image(),
          uploadFiles: config.uploadFiles,
        }),
      canUpload &&
        uploadButton({
          title: t.uploadFile,
          accept: ".pdf,.doc,.docx,.xls,.xlsx,.zip,.txt",
          icon: ICONS.drop(),
          uploadFiles: config.uploadFiles,
        }),
      canUpload &&
        uploadButton({
          title: t.uploadVideo,
          accept: "video/mp4,video/webm",
          icon: ICONS.video(),
          uploadFiles: config.uploadFiles,
        }),
      btn(ICONS.youtube(), {
        title: t.youtube,
        run: () => {
          const url = window.prompt(t.youtubePrompt, "https://www.youtube.com/watch?v=")
          if (!url) return
          editor
            .chain()
            .focus()
            .insertContent({ type: "video", attrs: { src: url, kind: "youtube" } })
            .run()
        },
      }),
      btn(ICONS.table(), {
        title: t.insertTable,
        run: () => editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(),
      }),
      btn(ICONS.hr(), {
        title: t.horizontalRule,
        run: () => editor.chain().focus().setHorizontalRule().run(),
      }),
    ])
  },

  utilities(editor, t) {
    return group([
      (() => {
        // Special-case: the InvisibleCharacters extension only mutates its
        // storage (not the doc nor the selection), so neither `update` nor
        // `selectionUpdate` fire. We sync the `is-active` class manually
        // after each click.
        const b = btn(ICONS.invisible(), {
          title: t.invisibleChars,
          editor,
          run: () => {
            editor.commands.toggleInvisibleCharacters?.()
            const v = editor.storage.invisibleCharacters?.visibility
            const visible = typeof v === "function" ? v() : !!v
            b.classList.toggle("is-active", visible)
          },
        })
        return b
      })(),
      btn(ICONS.blockquote(), {
        title: t.quote,
        editor,
        run: () => editor.chain().focus().toggleBlockquote().run(),
        activeWhen: () => editor.isActive("blockquote"),
      }),
    ])
  },

  history(editor, t) {
    return group([
      btn(ICONS.undo(), { title: t.undo, run: () => editor.chain().focus().undo().run() }),
      btn(ICONS.redo(), { title: t.redo, run: () => editor.chain().focus().redo().run() }),
    ])
  },
}

export function buildToolbar(editor, root, config = {}) {
  const resolved = {
    groups: config.groups || DEFAULT_GROUPS,
    textSizes: config.textSizes || DEFAULT_TEXT_SIZES,
    textColors: config.textColors || DEFAULT_TEXT_COLORS,
    highlights: config.highlights || DEFAULT_HIGHLIGHTS,
    fontFamilies: config.fontFamilies || DEFAULT_FONT_FAMILIES,
    lineHeights: config.lineHeights || DEFAULT_LINE_HEIGHTS,
    uploadFiles: config.uploadFiles,
    custom: config.custom || [],
  }
  const labels = { ...DEFAULT_LABELS, ...(config.labels || {}) }

  root.innerHTML = ""

  resolved.groups.forEach((name) => {
    const build = GROUPS[name]
    if (!build) {
      console.warn(`[Tiptapex] unknown toolbar group "${name}"`)
      return
    }
    root.appendChild(build(editor, labels, resolved))
  })

  if (resolved.custom.length > 0) {
    root.appendChild(
      group(
        resolved.custom.map((c) =>
          btn(typeof c.icon === "function" ? c.icon() : c.icon, {
            title: c.title,
            editor,
            run: () => c.run(editor),
            activeWhen: c.activeWhen ? () => c.activeWhen(editor) : undefined,
          })
        )
      )
    )
  }
}
