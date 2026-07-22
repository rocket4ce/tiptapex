// Ensures the document always ends with an empty paragraph so the user can
// click below the last node to start typing. Mirrors the deprecated
// @tiptap/extension-trailing-node behaviour.
import { Extension } from "@tiptap/core"
import { Plugin, PluginKey } from "@tiptap/pm/state"

export const TrailingNode = Extension.create({
  name: "trailingNode",

  addOptions() {
    return { nodeName: "paragraph" }
  },

  addProseMirrorPlugins() {
    const nodeName = this.options.nodeName
    const editor = this.editor

    return [
      new Plugin({
        key: new PluginKey("trailingNode"),
        appendTransaction(_transactions, _oldState, newState) {
          const { doc, schema, tr } = newState
          const type = schema.nodes[nodeName]
          if (!type || !editor) return

          const last = doc.lastChild
          if (!last || last.type.name !== nodeName || last.content.size !== 0) {
            return tr.insert(doc.content.size, type.create())
          }
        },
      }),
    ]
  },
})
