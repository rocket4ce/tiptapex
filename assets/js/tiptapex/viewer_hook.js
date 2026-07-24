// Read-only Tiptap renderer. Gives exactly the same node rendering as the
// editor (task lists, tables, code, resizable images honoring saved widths,
// videos, etc.) without the contenteditable surface, toolbar, file handler
// or collaboration plumbing.
//
// The hook reads `data-ttx-doc` (Tiptap's ProseMirror JSON doc) and replaces
// the server-rendered fallback (`data-ttx-role="fallback"`, produced by
// `Tiptapex.Renderer.to_html/2`) once the client-side render is up. If
// parsing fails the fallback stays — the page is never blank.
import { Editor } from "@tiptap/core"
import { StarterKit } from "@tiptap/starter-kit"
import { CharacterCount } from "@tiptap/extension-character-count"
import { Color } from "@tiptap/extension-color"
import { FontFamily } from "@tiptap/extension-font-family"
import { Highlight } from "@tiptap/extension-highlight"
import { Link } from "@tiptap/extension-link"
import { TaskList, TaskItem } from "@tiptap/extension-list"
import { Table, TableCell, TableHeader, TableRow } from "@tiptap/extension-table"
import { TextAlign } from "@tiptap/extension-text-align"
import { TextStyle } from "@tiptap/extension-text-style"
import { Typography } from "@tiptap/extension-typography"
import { UniqueID } from "@tiptap/extension-unique-id"

import { ResizableImage } from "./extensions/resizable-image"
import { Video } from "./extensions/video"
import { FontSize } from "./extensions/font-size"
import { LineHeight } from "./extensions/line-height"
import { BackgroundColor } from "./extensions/background-color"
import { PageSetup } from "./extensions/page-setup"
import { PageBreak } from "./extensions/page-break"
import { Pagination } from "./pagination"
import { resolvePageSetup } from "./page"
import { parseJSON } from "./config"

export function buildViewerExtensions(opts = {}) {
  const { page = true, defaultPage = null, pageGutter = undefined, locale = undefined } = opts

  const exts = [
    // StarterKit v3 bundles Link; we add our own configured copy below.
    StarterKit.configure({ link: false }),
    Color,
    BackgroundColor,
    TextStyle,
    FontFamily.configure({ types: ["textStyle"] }),
    FontSize,
    LineHeight,
    TextAlign.configure({ types: ["heading", "paragraph"] }),
    Highlight.configure({ multicolor: true }),
    ResizableImage.configure({ inline: false, allowBase64: false }),
    Link.configure({
      openOnClick: true,
      autolink: true,
      HTMLAttributes: { rel: "noopener nofollow", target: "_blank" },
    }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Table.configure({ resizable: false }),
    TableRow,
    TableHeader,
    TableCell,
    Typography,
    CharacterCount,
    UniqueID.configure({ types: ["heading", "paragraph", "blockquote"] }),
    Video,
    // A document with a page setup renders paginated here too — same
    // measuring plugin as the editor, so a preview matches what the editor
    // (and the PDF) will show.
    PageBreak,
    page && PageSetup.configure({ defaultPage }),
    page && Pagination.configure({ gutter: pageGutter, locale }),
  ].filter(Boolean)

  return typeof opts.extend === "function" ? opts.extend(exts) : exts
}

export function makeViewerHook(staticOpts = {}) {
  return {
    mounted() {
      const target = this.el.querySelector("[data-ttx-role='viewer-target']") || this.el
      const json = parseJSON(this.el.dataset.ttxDoc)
      if (!json) {
        // Nothing to hydrate — the server-rendered HTML stays as a fallback.
        return
      }

      const raw = this.el.dataset.ttxPage
      const pageAttr = "ttxPage" in this.el.dataset ? (raw === "false" ? false : parseJSON(raw, null)) : null
      const { doc, page } = resolvePageSetup(json, pageAttr)

      this.editor = new Editor({
        element: target,
        editable: false,
        content: doc,
        extensions: buildViewerExtensions({ defaultPage: page, ...staticOpts }),
      })

      this.el.tiptapexEditor = this.editor

      // Replace the SSR HTML fallback (sibling div) once the live render is
      // up.
      const fallback = this.el.querySelector("[data-ttx-role='fallback']")
      if (fallback) fallback.remove()
    },

    destroyed() {
      if (this.editor) this.editor.destroy()
    },
  }
}

export const TiptapexViewerHook = makeViewerHook()
