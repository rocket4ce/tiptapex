// Page setup as a document attribute.
//
// The paper size, orientation, margins, header/footer slots and page
// numbering live on the ProseMirror `doc` node under `attrs.page`, so they
// travel with `editor.getJSON()` and land in the same column as the content.
// `Tiptapex.Page` reads exactly this shape on the server.
//
//   editor.commands.setPageOptions({ size: "legal" })     // merge a patch
//   editor.commands.setPageOptions(null)                  // stop paginating
//   editor.getAttributes("doc").page                      // read it back
//
// Note for collaborative editors: y-prosemirror syncs the document's
// *content*, not the top-level node's attributes. Pass the page setup from
// the server (`page={...}` on the component) so every peer starts from the
// same configuration.
import { Extension } from "@tiptap/core"

import { normalizePage, mergePage } from "../page"

export const PageSetup = Extension.create({
  name: "pageSetup",

  addOptions() {
    return {
      // Seeds `doc.attrs.page` for documents that carry none — this is how
      // the server-side `page` attribute reaches collaborative sessions.
      defaultPage: null,
    }
  },

  addGlobalAttributes() {
    const defaultPage = normalizePage(this.options.defaultPage)

    return [
      {
        types: ["doc"],
        attributes: {
          page: {
            default: defaultPage,
            // The doc node has no DOM representation: there is nothing to
            // parse from and nothing to render into.
            parseHTML: () => null,
            renderHTML: () => ({}),
            keepOnSplit: false,
          },
        },
      },
    ]
  },

  addCommands() {
    return {
      // Merges a partial patch over the current setup. `null` removes the
      // page setup entirely (the document goes back to a continuous flow).
      setPageOptions:
        (patch) =>
        ({ state, tr, dispatch }) => {
          if (typeof tr.setDocAttribute !== "function") {
            console.error(
              "[Tiptapex] page setup needs prosemirror-state >= 1.4.2 " +
                "(Transaction#setDocAttribute). Update @tiptap/pm."
            )
            return false
          }

          const next = patch === null ? null : mergePage(state.doc.attrs.page, patch)
          if (dispatch) tr.setDocAttribute("page", next)
          return true
        },
    }
  },
})

// Reads the (normalised) page setup off an editor, or null when the document
// is not paginated.
export function pageOf(editor) {
  return normalizePage(editor?.state?.doc?.attrs?.page)
}
