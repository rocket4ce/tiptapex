// Background color via textStyle (paired with @tiptap/extension-text-style).
// Adds `background-color: <value>` to an inline span without depending on
// the Highlight extension (which uses <mark> with limited palette).
import { Extension } from "@tiptap/core"

export const BackgroundColor = Extension.create({
  name: "backgroundColor",

  addOptions() {
    return { types: ["textStyle"] }
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          backgroundColor: {
            default: null,
            parseHTML: (el) => el.style.backgroundColor || null,
            renderHTML: (attrs) =>
              attrs.backgroundColor
                ? { style: `background-color: ${attrs.backgroundColor}` }
                : {},
          },
        },
      },
    ]
  },

  addCommands() {
    return {
      setBackgroundColor:
        (color) =>
        ({ chain }) =>
          chain().setMark("textStyle", { backgroundColor: color }).run(),
      unsetBackgroundColor:
        () =>
        ({ chain }) =>
          chain()
            .setMark("textStyle", { backgroundColor: null })
            .removeEmptyTextStyle()
            .run(),
    }
  },
})
