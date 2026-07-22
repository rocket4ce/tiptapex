// Tiptapex — Tiptap v3 for Phoenix LiveView.
//
// Main entry point. Import it from your app bundle:
//
//   import { hooks as tiptapex } from "tiptapex"
//
//   const liveSocket = new LiveSocket("/live", Socket, {
//     hooks: { ...yourHooks, ...tiptapex },
//   })
//
// Collaboration is a separate entry point ("tiptapex/collaboration") so the
// yjs stack stays out of bundles that don't use it:
//
//   import { makeEditorHook, TiptapexViewerHook } from "tiptapex"
//   import { CollabPlugin } from "tiptapex/collaboration"
//
//   const hooks = {
//     TiptapexEditor: makeEditorHook({ collab: CollabPlugin }),
//     TiptapexViewer: TiptapexViewerHook,
//   }

export {
  TiptapexHook,
  makeEditorHook,
  buildExtensions,
  uploadAndInsert,
  DEFAULT_UPLOAD_MIME_TYPES,
} from "./editor_hook"

export { TiptapexViewerHook, makeViewerHook, buildViewerExtensions } from "./viewer_hook"

export {
  buildToolbar,
  ICONS,
  DEFAULT_GROUPS,
  DEFAULT_LABELS,
  DEFAULT_TEXT_SIZES,
  DEFAULT_TEXT_COLORS,
  DEFAULT_HIGHLIGHTS,
  DEFAULT_FONT_FAMILIES,
  DEFAULT_LINE_HEIGHTS,
} from "./toolbar"

export { attachTableMenu, DEFAULT_TABLE_LABELS } from "./table-menu"

export { ResizableImage } from "./extensions/resizable-image"
export { Video, toYoutubeEmbed } from "./extensions/video"
export { FontSize } from "./extensions/font-size"
export { LineHeight } from "./extensions/line-height"
export { BackgroundColor } from "./extensions/background-color"
export { TrailingNode } from "./extensions/trailing-node"
export { SelectionPreserve } from "./extensions/selection-preserve"

export { DEFAULTS, EMPTY_DOC, ATTACHMENT_MIME } from "./config"

import { TiptapexHook } from "./editor_hook"
import { TiptapexViewerHook } from "./viewer_hook"

// Ready-to-spread hook map for the LiveSocket.
export const hooks = {
  TiptapexEditor: TiptapexHook,
  TiptapexViewer: TiptapexViewerHook,
}
