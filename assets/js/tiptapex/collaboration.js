// Realtime collaboration for Tiptapex: a Yjs provider that syncs through a
// Phoenix Channel, plus the `CollabPlugin` glue consumed by
// `makeEditorHook({ collab: CollabPlugin })`.
//
// This module is a SEPARATE entry point ("tiptapex/collaboration") so apps
// that don't use collaboration never pull `yjs` / `y-protocols` /
// `@tiptap/extension-collaboration*` into their bundle. Those packages are
// optional peer dependencies — install them only if you import this file.
//
// Wire protocol (see `Tiptapex.Collab.Channel` on the Elixir side):
//   client → server: "client_sync"      (binary Yjs sync message)
//                    "client_awareness" (binary Yjs awareness update)
//                    "request_state"    (asks peers to broadcast their state)
//   server → client: "server_sync"      (broadcast from another peer)
//                    "server_awareness"
//                    "request_state"    (someone else just joined)
//
// Implements the same surface as the standard y-websocket provider so
// y-prosemirror + Collaboration/CollaborationCaret extensions work without
// modification.

import * as Y from "yjs"
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from "y-protocols/awareness"
import * as syncProtocol from "y-protocols/sync"
import * as encoding from "lib0/encoding"
import * as decoding from "lib0/decoding"
import { prosemirrorJSONToYXmlFragment } from "y-prosemirror"
import { Collaboration } from "@tiptap/extension-collaboration"
import { CollaborationCaret } from "@tiptap/extension-collaboration-caret"
import { Socket } from "phoenix"

// Tiptap's Collaboration extension stores the document under this Y.Doc
// field unless configured otherwise.
const Y_FIELD = "default"

const messageSync = 0
const messageAwareness = 1

export class PhoenixCollabProvider {
  constructor({ socket, topic, doc, awareness, user }) {
    this.doc = doc || new Y.Doc()
    this.awareness = awareness || new Awareness(this.doc)
    this.user = user
    this.topic = topic
    this.socket = socket
    this.synced = false

    // Minimal Observable surface so Tiptap's CollaborationCaret extension
    // (which calls provider.on/off) is happy.
    this._listeners = Object.create(null)

    // Set initial awareness state for this user (name, color, …). Tiptap's
    // CollaborationCaret picks these up automatically.
    // If no explicit name is given, use the local-part of the email so the
    // caret label stays short and legible. The full email lives in
    // `user.email` for any future "who is editing" UI.
    const email = user?.email || ""
    const fallbackName = email.includes("@") ? email.split("@")[0] : email
    this.awareness.setLocalState({
      user: {
        id: user?.id || "anon",
        name: user?.name || fallbackName || "Anonymous",
        email,
        color: user?.color || "hsl(220, 70%, 55%)",
      },
    })

    this.channel = socket.channel(topic)

    this.channel.on("server_sync", (payload) => {
      const buf = toUint8Array(payload)
      this._readSyncMessage(buf)
    })

    this.channel.on("server_awareness", (payload) => {
      const buf = toUint8Array(payload)
      applyAwarenessUpdate(this.awareness, buf, this)
    })

    this.channel.on("request_state", () => {
      // Another peer just joined and is asking for our state — answer.
      this._sendSyncStep1()
    })

    // Local doc updates → broadcast to peers
    this._docUpdateHandler = (update, origin) => {
      if (origin === this) return
      const encoder = encoding.createEncoder()
      encoding.writeVarUint(encoder, messageSync)
      syncProtocol.writeUpdate(encoder, update)
      this._sendBinary("client_sync", encoding.toUint8Array(encoder))
    }
    this.doc.on("update", this._docUpdateHandler)

    // Local awareness updates → broadcast
    this._awarenessUpdateHandler = ({ added, updated, removed }, origin) => {
      if (origin === this) return
      const changed = added.concat(updated).concat(removed)
      const update = encodeAwarenessUpdate(this.awareness, changed)
      this._sendBinary("client_awareness", update)
    }
    this.awareness.on("update", this._awarenessUpdateHandler)

    this.channel
      .join()
      .receive("ok", (resp) => {
        this.peerInfo = resp
        // Step 1 of the Yjs sync handshake: announce our state vector so a
        // peer can send back the diff.
        this._sendSyncStep1()
        // Also ask peers explicitly (covers the case where we're the second
        // peer to join an already-active room).
        this.channel.push("request_state", {})
      })
      .receive("error", (err) => console.error("[Tiptapex collab] join error", err))
  }

  on(event, fn) {
    ;(this._listeners[event] ||= new Set()).add(fn)
  }

  off(event, fn) {
    this._listeners[event]?.delete(fn)
  }

  emit(event, ...args) {
    this._listeners[event]?.forEach((fn) => {
      try {
        fn(...args)
      } catch (e) {
        console.error("[Tiptapex collab] listener error", e)
      }
    })
  }

  destroy() {
    if (this.channel) this.channel.leave()
    if (this.awareness) {
      removeAwarenessStates(this.awareness, [this.doc.clientID], this)
      this.awareness.off("update", this._awarenessUpdateHandler)
    }
    if (this.doc) this.doc.off("update", this._docUpdateHandler)
  }

  _sendSyncStep1() {
    const encoder = encoding.createEncoder()
    encoding.writeVarUint(encoder, messageSync)
    syncProtocol.writeSyncStep1(encoder, this.doc)
    this._sendBinary("client_sync", encoding.toUint8Array(encoder))
  }

  _sendBinary(event, uint8) {
    // Phoenix.js supports ArrayBuffer payloads for binary channel messages.
    this.channel.push(event, uint8.buffer.slice(uint8.byteOffset, uint8.byteOffset + uint8.byteLength))
  }

  _readSyncMessage(buf) {
    const decoder = decoding.createDecoder(buf)
    const messageType = decoding.readVarUint(decoder)

    switch (messageType) {
      case messageSync: {
        const encoder = encoding.createEncoder()
        encoding.writeVarUint(encoder, messageSync)
        const syncMessageType = syncProtocol.readSyncMessage(
          decoder,
          encoder,
          this.doc,
          this
        )
        if (encoding.length(encoder) > 1) {
          this._sendBinary("client_sync", encoding.toUint8Array(encoder))
        }
        if (syncMessageType === syncProtocol.messageYjsSyncStep2 && !this.synced) {
          this.synced = true
        }
        break
      }
      case messageAwareness:
        applyAwarenessUpdate(this.awareness, decoding.readVarUint8Array(decoder), this)
        break
      default:
        break
    }
  }
}

// Plugin consumed by `makeEditorHook({ collab: CollabPlugin })`. Keeping the
// create/extensions/destroy lifecycle here means the editor hook itself has
// no static dependency on yjs.
export const CollabPlugin = {
  // Creates the Y.Doc, Phoenix Socket and provider for one editor instance.
  create({ topic, socketPath, user, csrfToken, socketParams }) {
    const doc = new Y.Doc()
    const socket = new Socket(socketPath || "/socket", {
      params: { _csrf_token: csrfToken, ...(socketParams || {}) },
    })
    socket.connect()
    const provider = new PhoenixCollabProvider({ socket, topic, doc, user })
    return { doc, socket, provider, user }
  },

  // Tiptap extensions for a collab session created above.
  extensions(collab) {
    return [
      Collaboration.configure({ document: collab.doc }),
      CollaborationCaret.configure({
        provider: collab.provider,
        user: {
          id: collab.user?.id,
          name: collab.user?.name || collab.user?.email || "Anonymous",
          color: collab.user?.color || "hsl(220, 70%, 55%)",
        },
      }),
    ]
  },

  // Replaces the document content THROUGH the Y.Doc. With collaboration
  // active, `editor.commands.setContent()` is unreliable: the y-prosemirror
  // sync plugin re-renders the editor from the Y.Doc and can revert the
  // change (content flashes and disappears). Writing the fragment inside a
  // Yjs transaction is atomic, sticks locally, and propagates to peers.
  setContent(collab, editor, json) {
    const fragment = collab.doc.getXmlFragment(Y_FIELD)
    collab.doc.transact(() => {
      fragment.delete(0, fragment.length)
      prosemirrorJSONToYXmlFragment(editor.schema, json, fragment)
    })
  },

  destroy(collab) {
    collab.provider?.destroy()
    collab.doc?.destroy()
    collab.socket?.disconnect()
  },
}

function toUint8Array(payload) {
  if (payload instanceof Uint8Array) return payload
  if (payload instanceof ArrayBuffer) return new Uint8Array(payload)
  if (payload && payload.data instanceof ArrayBuffer) return new Uint8Array(payload.data)
  return new Uint8Array(payload)
}
