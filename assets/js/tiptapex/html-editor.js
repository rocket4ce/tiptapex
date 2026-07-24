// CodeMirror 6 surface for the HTML source view — optional entry point.
//
// Kept out of the main bundle (like "tiptapex/collaboration") so the
// CodeMirror packages stay out of bundles that don't use them. Install the
// optional peers and build your hook with it:
//
//   npm install codemirror @codemirror/lang-html @codemirror/view @codemirror/commands
//
//   import { makeEditorHook } from "tiptapex"
//   import { CodeMirrorHtmlEditor } from "tiptapex/html-editor"
//
//   const hooks = { TiptapexEditor: makeEditorHook({ htmlEditor: CodeMirrorHtmlEditor }) }
//
// The object implements the html-view surface contract — any object with
// the same shape (create/getValue/setValue/focus/destroy) can be passed as
// `htmlEditor` instead, e.g. a Monaco- or Ace-backed one.
import { EditorView, basicSetup } from "codemirror"
import { keymap } from "@codemirror/view"
import { indentWithTab } from "@codemirror/commands"
import { html } from "@codemirror/lang-html"

// Visuals ride on the ttx-* theme tokens so the code editor follows the
// host's light/dark theme like the rest of the component.
const theme = EditorView.theme({
  "&": {
    fontSize: "0.85rem",
    backgroundColor: "transparent",
    color: "var(--ttx-text)",
  },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": {
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    lineHeight: "1.6",
  },
  ".cm-content": { padding: "1.25rem 0.5rem" },
  ".cm-gutters": {
    backgroundColor: "var(--ttx-surface-2)",
    color: "color-mix(in oklch, var(--ttx-text) 45%, transparent)",
    border: "none",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in oklch, var(--ttx-text) 5%, transparent)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "color-mix(in oklch, var(--ttx-text) 8%, transparent)",
  },
})

export const CodeMirrorHtmlEditor = {
  create(container, { value, onChange }) {
    return new EditorView({
      doc: value || "",
      parent: container,
      extensions: [
        basicSetup,
        html(),
        keymap.of([indentWithTab]),
        EditorView.lineWrapping,
        EditorView.updateListener.of((update) => {
          if (update.docChanged) onChange()
        }),
        theme,
      ],
    })
  },

  getValue(view) {
    return view.state.doc.toString()
  },

  setValue(view, value) {
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: value } })
  },

  focus(view) {
    view.focus()
  },

  destroy(view) {
    view.destroy()
  },
}
