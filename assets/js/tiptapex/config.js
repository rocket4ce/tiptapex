// Shared defaults and small helpers for the Tiptapex hooks.
//
// Every app-facing knob (event names, upload field name, socket path…) has a
// default here and can be overridden per-editor through the `data-ttx-*`
// attributes emitted by the `Tiptapex.Components` HEEx components.

export const DEFAULTS = {
  changeEvent: "tiptapex_change",
  uploadedEvent: "tiptapex_uploaded",
  uploadScopeName: "scope",
  socketPath: "/socket",
  debounceMs: 400,
  placeholder: "Start writing or paste content…",
  countTemplate: "{chars} characters · {words} words",
}

export const EMPTY_DOC = { type: "doc", content: [{ type: "paragraph" }] }

// MIME type used for dragging already-uploaded attachments from a host
// sidebar into the editor. The drag source marks items with a
// `data-ttx-attachment` JSON payload ({url, content_type, filename}).
export const ATTACHMENT_MIME = "application/x-tiptapex-attachment"

export function parseJSON(raw, fallback = null) {
  if (!raw) return fallback
  try {
    return JSON.parse(raw)
  } catch (_e) {
    return fallback
  }
}

export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}
