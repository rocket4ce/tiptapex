// Preserve the user's selection when the editor blurs (e.g. when they click
// the toolbar). Reapplies on focus.
import { Extension } from "@tiptap/core"
import { Plugin, PluginKey, TextSelection } from "@tiptap/pm/state"
import { Decoration, DecorationSet } from "@tiptap/pm/view"

const key = new PluginKey("selectionPreserve")

export const SelectionPreserve = Extension.create({
  name: "selectionPreserve",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key,
        state: {
          init: () => ({ from: null, to: null }),
          apply(tr, prev) {
            const meta = tr.getMeta(key)
            if (meta) return meta
            if (tr.docChanged && prev.from != null && prev.to != null) {
              return {
                from: tr.mapping.map(prev.from),
                to: tr.mapping.map(prev.to),
              }
            }
            return prev
          },
        },
        props: {
          handleDOMEvents: {
            blur(view) {
              const { from, to } = view.state.selection
              const tr = view.state.tr.setMeta(key, { from, to })
              view.dispatch(tr)
              return false
            },
            focus(view) {
              const saved = key.getState(view.state)
              if (!saved || saved.from == null) return false
              const $from = view.state.doc.resolve(saved.from)
              const $to = view.state.doc.resolve(saved.to)
              const tr = view.state.tr.setSelection(new TextSelection($from, $to))
              view.dispatch(tr)
              return false
            },
          },
          decorations(state) {
            // Mark the saved selection visually when the editor is blurred.
            const isFocused = (state.selection.empty && state.selection.from === 0) === false
            if (isFocused) return DecorationSet.empty
            const { from, to } = key.getState(state) || {}
            if (from == null || to == null || from === to) return DecorationSet.empty
            return DecorationSet.create(state.doc, [
              Decoration.inline(from, to, { class: "ProseMirror-saved-selection" }),
            ])
          },
        },
      }),
    ]
  },
})
