// Editable HTML source view for the Tiptapex editor.
//
// `attachHtmlView(editor, rootEl, opts)` mounts a hidden <textarea> next to
// the WYSIWYG surface and returns a small controller:
//
//   const view = attachHtmlView(editor, rootEl, { debounceMs: 400 })
//   view.toggle()    // switch between WYSIWYG and HTML source
//   view.isActive()  // true while the source view is showing
//   view.destroy()
//
// While the source view is active the textarea shows a pretty-printed
// `editor.getHTML()` and edits are parsed back into the document
// (debounced), so the hook's normal update pipeline — change events,
// hidden-input sync, character count — keeps working unchanged. Anything
// the schema doesn't know (scripts, unknown tags/attributes) is dropped by
// ProseMirror's parser on the way back in, exactly as it would be for
// pasted HTML.
//
// `opts.applyJSON` overrides how the parsed document is applied — the hook
// uses it under collaboration to write through the Y.Doc instead of a
// plain setContent (which the y-prosemirror sync plugin would revert).
//
// `opts.codeEditor` upgrades the plain textarea to a full code editor. It
// must implement the surface contract:
//
//   create(container, {value, onChange}) -> instance
//   getValue(instance) -> string
//   setValue(instance, string)
//   focus(instance)
//   destroy(instance)
//
// `CodeMirrorHtmlEditor` from "tiptapex/html-editor" is the ready-made one.
import { DOMParser as ProseMirrorDOMParser } from "@tiptap/pm/model"

// Block-level tags in the Tiptapex schema — these get their own line when
// pretty-printing. Inline tags (strong, em, a, span…) stay in the text flow.
const BLOCK_TAGS = new Set([
  "p", "h1", "h2", "h3", "h4", "h5", "h6",
  "ul", "ol", "li",
  "table", "thead", "tbody", "tr", "th", "td", "colgroup", "col",
  "blockquote", "pre", "hr", "div", "figure", "figcaption",
  "video", "iframe", "img",
])

// Tags that never wrap content, so they don't change the indent level.
const VOID_TAGS = new Set(["hr", "img", "br", "col", "source"])

// Pretty-prints editor HTML: one line per block tag, two-space indent.
// Content inside <pre> is whitespace-sensitive and is emitted verbatim.
export function formatHtml(html) {
  const tokens = html.split(/(<[^>]+>)/g).filter(Boolean)
  const out = []
  let indent = 0
  let preDepth = 0
  // Tracks what was emitted last so closing tags of leaf blocks
  // (`<p>text</p>`) stay inline while container closers (`</ul>`) get
  // their own line.
  let last = "start"

  const line = (s) => out.push((last === "start" ? "" : "\n") + "  ".repeat(indent) + s)

  for (const tok of tokens) {
    const m = /^<(\/?)([a-zA-Z][^\s/>]*)/.exec(tok)

    if (preDepth > 0) {
      out.push(tok)
      if (m && m[2].toLowerCase() === "pre") preDepth += m[1] ? -1 : 1
      if (preDepth === 0) last = "close"
      continue
    }

    if (!m) {
      out.push(tok)
      last = "text"
      continue
    }

    const closing = !!m[1]
    const tag = m[2].toLowerCase()

    if (!BLOCK_TAGS.has(tag)) {
      out.push(tok)
      last = "text"
      continue
    }

    if (VOID_TAGS.has(tag)) {
      line(tok)
      last = "close"
    } else if (!closing) {
      line(tok)
      last = "open"
      if (tag === "pre") preDepth = 1
      else indent++
    } else {
      indent = Math.max(0, indent - 1)
      if (last === "close") line(tok)
      else out.push(tok)
      last = "close"
    }
  }

  return out.join("")
}

// Parses an HTML string into a Tiptap JSON document using the editor's own
// schema — the same rules applied to pasted content.
export function htmlToJSON(editor, html) {
  const dom = new window.DOMParser().parseFromString(html, "text/html")
  return ProseMirrorDOMParser.fromSchema(editor.schema).parse(dom.body).toJSON()
}

// Plain-textarea surface — the zero-dependency default.
function textareaSurface(contentEl, onInput) {
  const textarea = document.createElement("textarea")
  textarea.className = "ttx-html-view"
  textarea.setAttribute("data-ttx-role", "html-view")
  textarea.spellcheck = false
  textarea.setAttribute("autocomplete", "off")
  textarea.setAttribute("autocapitalize", "off")
  contentEl.insertAdjacentElement("afterend", textarea)
  textarea.addEventListener("input", onInput)

  return {
    get: () => textarea.value,
    set: (value) => {
      textarea.value = value
    },
    focus: () => textarea.focus(),
    destroy: () => {
      textarea.removeEventListener("input", onInput)
      textarea.remove()
    },
  }
}

// Code-editor surface backed by a host-provided factory (e.g.
// CodeMirrorHtmlEditor). Programmatic set() must not re-trigger onInput —
// the factory's onChange fires for every document change, so it is muted
// around setValue.
function codeEditorSurface(contentEl, factory, onInput) {
  const holder = document.createElement("div")
  holder.className = "ttx-html-view is-code"
  holder.setAttribute("data-ttx-role", "html-view")
  contentEl.insertAdjacentElement("afterend", holder)

  let muted = false
  const instance = factory.create(holder, {
    value: "",
    onChange: () => {
      if (!muted) onInput()
    },
  })

  return {
    get: () => factory.getValue(instance),
    set: (value) => {
      muted = true
      try {
        factory.setValue(instance, value)
      } finally {
        muted = false
      }
    },
    focus: () => factory.focus(instance),
    destroy: () => {
      factory.destroy(instance)
      holder.remove()
    },
  }
}

export function attachHtmlView(editor, root, opts = {}) {
  const debounceMs = opts.debounceMs || 400
  const contentEl = root.querySelector("[data-ttx-role='editor']") || root

  let active = false
  let dirty = false
  let debounce

  // The source view round-trips the *content*. Document-level attributes —
  // the page setup lives on the `doc` node, which has no DOM representation —
  // are carried over explicitly, so editing the HTML never silently drops the
  // page layout.
  const apply = () => {
    dirty = false
    const json = htmlToJSON(editor, surface.get())
    const attrs = editor.state.doc.attrs

    if (attrs && Object.keys(attrs).length > 0) {
      json.attrs = { ...attrs, ...(json.attrs || {}) }
    }

    if (typeof opts.applyJSON === "function") {
      opts.applyJSON(json)
    } else {
      editor.commands.setContent(json, { emitUpdate: true })
    }
  }

  const onInput = () => {
    dirty = true
    clearTimeout(debounce)
    debounce = setTimeout(apply, debounceMs)
  }

  const surface = opts.codeEditor
    ? codeEditorSurface(contentEl, opts.codeEditor, onInput)
    : textareaSurface(contentEl, onInput)

  return {
    isActive: () => active,

    // Re-reads the document into the source view (e.g. after the server
    // pushed new content via set_content while the view was showing).
    refresh() {
      if (!active) return
      clearTimeout(debounce)
      dirty = false
      surface.set(formatHtml(editor.getHTML()))
    },

    toggle() {
      active = !active
      if (active) {
        surface.set(formatHtml(editor.getHTML()))
        root.classList.add("ttx-html-mode")
        editor.setEditable(false)
        surface.focus()
      } else {
        clearTimeout(debounce)
        if (dirty) apply()
        root.classList.remove("ttx-html-mode")
        editor.setEditable(true)
        editor.commands.focus()
      }
      return active
    },

    destroy() {
      clearTimeout(debounce)
      surface.destroy()
    },
  }
}
