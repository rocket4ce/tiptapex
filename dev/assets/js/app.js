// Demo app bundle. This mirrors exactly what a host app's app.js does.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { makeEditorHook, TiptapexViewerHook } from "tiptapex"
import { CollabPlugin } from "tiptapex/collaboration"

const hooks = {
  TiptapexEditor: makeEditorHook({ collab: CollabPlugin }),
  TiptapexViewer: TiptapexViewerHook,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks,
})

liveSocket.connect()
window.liveSocket = liveSocket
