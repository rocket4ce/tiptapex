// A forced page break.
//
// Renders as `<div data-page-break>` — the same markup
// `Tiptapex.Renderer.Nodes` emits server-side — so the break survives the
// HTML source view round-trip and lands in the PDF as
// `break-after: page`.
//
//   editor.commands.setPageBreak()
//   Cmd/Ctrl+Shift+Enter
import { Node, mergeAttributes } from "@tiptap/core"

export const PageBreak = Node.create({
  name: "pageBreak",

  group: "block",

  // No content, and selectable as a whole so it can be deleted with a
  // single Backspace and dragged around by the drag handle.
  atom: true,
  selectable: true,
  draggable: true,

  parseHTML() {
    return [{ tag: "div[data-page-break]" }, { tag: "hr[data-page-break]" }]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        "data-page-break": "true",
        class: "ttx-page-break",
      }),
    ]
  },

  addCommands() {
    return {
      setPageBreak:
        () =>
        ({ commands }) =>
          commands.insertContent({ type: this.name }),
    }
  },

  addKeyboardShortcuts() {
    // Mod-Enter is already taken by HardBreak (and by exitCode inside code
    // blocks), so the page break sits one modifier further out.
    return {
      "Mod-Shift-Enter": () => this.editor.commands.setPageBreak(),
    }
  },
})
