// Custom Tiptap extension for line-height support.
// Tiptap doesn't ship a stable LineHeight extension; this one extends
// the existing paragraph/heading nodes with a `line-height` attribute
// that is serialized to inline `style="line-height: ..."`.
import { Extension } from "@tiptap/core"

export const LineHeight = Extension.create({
  name: "lineHeight",

  addOptions() {
    return {
      types: ["paragraph", "heading"],
      defaults: ["1", "1.15", "1.5", "2"],
    }
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          lineHeight: {
            default: null,
            parseHTML: (el) => el.style.lineHeight || null,
            renderHTML: (attrs) =>
              attrs.lineHeight ? { style: `line-height: ${attrs.lineHeight}` } : {},
          },
        },
      },
    ]
  },

  addCommands() {
    return {
      setLineHeight:
        (value) =>
        ({ commands }) =>
          this.options.types
            .map((t) => commands.updateAttributes(t, { lineHeight: value }))
            .every(Boolean),
      unsetLineHeight:
        () =>
        ({ commands }) =>
          this.options.types
            .map((t) => commands.resetAttributes(t, "lineHeight"))
            .every(Boolean),
    }
  },
})
