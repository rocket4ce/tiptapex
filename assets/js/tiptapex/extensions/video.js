// Custom Video node for Tiptap.
//
// Supports two `kind`s:
//
// - `"file"`     → an uploaded `<video controls src=...>` (mp4 / webm).
//                  Persisted exactly like images: the file lives in the
//                  host's storage, the schema just keeps the URL.
// - `"youtube"`  → an embedded YouTube `<iframe>`. We parse the URL to a
//                  canonical embed form so the user can paste either
//                  `youtu.be/<id>`, `youtube.com/watch?v=<id>`, or the
//                  embed URL itself.
//
// Like `ResizableImage` it persists a `width` attribute and renders four
// corner handles so the user can resize proportionally. The wrapper uses
// `aspect-ratio` so changing the width keeps the player's height in sync.
//
// The server-side renderer (Tiptapex.Renderer) emits the same markup shape
// so SSR output and client-hydrated output are identical.
import { Node, mergeAttributes } from "@tiptap/core"

const MIN_WIDTH = 160
const HANDLES = ["nw", "ne", "sw", "se"]

function toCssWidth(value) {
  if (value === null || value === undefined || value === "") return ""
  if (typeof value === "number") return `${value}px`
  return /^\d+(\.\d+)?$/.test(String(value)) ? `${value}px` : String(value)
}

/**
 * Extracts the YouTube video id from any of the common URL shapes and
 * returns the canonical embed URL. Returns null if the input doesn't
 * look like a YouTube link (caller may fall back to using the URL as-is).
 */
export function toYoutubeEmbed(raw) {
  if (!raw) return null
  let url
  try {
    url = new URL(raw)
  } catch (_) {
    return null
  }

  const host = url.hostname.replace(/^www\./, "")
  let id = null

  if (host === "youtu.be") {
    id = url.pathname.slice(1)
  } else if (host.endsWith("youtube.com")) {
    if (url.pathname.startsWith("/embed/")) {
      return url.toString()
    } else if (url.pathname === "/watch") {
      id = url.searchParams.get("v")
    } else if (url.pathname.startsWith("/shorts/")) {
      id = url.pathname.split("/")[2]
    }
  }

  return id ? `https://www.youtube.com/embed/${id}` : null
}

export const Video = Node.create({
  name: "video",
  group: "block",
  atom: true,
  selectable: true,
  draggable: true,

  addOptions() {
    return { HTMLAttributes: {} }
  },

  addAttributes() {
    return {
      src: { default: null },
      kind: { default: "file" },
      width: {
        default: null,
        parseHTML: (el) => {
          const attr = el.getAttribute("width") || el.style?.width
          if (!attr) return null
          return parseInt(attr, 10) || attr
        },
      },
      title: { default: null },
    }
  },

  parseHTML() {
    return [
      {
        tag: 'div[data-video="file"]',
        getAttrs: (el) => {
          const v = el.querySelector("video")
          return {
            kind: "file",
            src: v?.getAttribute("src"),
            width: el.style?.width || el.getAttribute("width"),
          }
        },
      },
      {
        tag: 'div[data-video="youtube"]',
        getAttrs: (el) => {
          const f = el.querySelector("iframe")
          return {
            kind: "youtube",
            src: f?.getAttribute("src"),
            width: el.style?.width || el.getAttribute("width"),
          }
        },
      },
    ]
  },

  renderHTML({ node, HTMLAttributes }) {
    const { src, kind, width, title } = node.attrs
    const widthStyle = width ? `width: ${toCssWidth(width)};` : ""

    if (kind === "youtube") {
      const embed = toYoutubeEmbed(src) || src
      return [
        "div",
        mergeAttributes(HTMLAttributes, {
          "data-video": "youtube",
          class: "ttx-video ttx-video-youtube",
          style: widthStyle,
        }),
        [
          "iframe",
          {
            src: embed,
            frameborder: "0",
            allowfullscreen: "true",
            allow:
              "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share",
            referrerpolicy: "strict-origin-when-cross-origin",
          },
        ],
      ]
    }

    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        "data-video": "file",
        class: "ttx-video ttx-video-file",
        style: widthStyle,
      }),
      [
        "video",
        {
          src,
          controls: "true",
          playsinline: "true",
          title: title || "",
          preload: "metadata",
        },
      ],
    ]
  },

  addCommands() {
    return {
      /**
       * Inserts a `video` node. `attrs` must include `kind` and `src`.
       */
      insertVideo:
        (attrs) =>
        ({ commands }) =>
          commands.insertContent({ type: this.name, attrs }),
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      const isYoutube = node.attrs.kind === "youtube"

      const wrapper = document.createElement("div")
      wrapper.className = `ttx-video ttx-video-wrapper ${
        isYoutube ? "ttx-video-youtube" : "ttx-video-file"
      }`
      wrapper.dataset.video = isYoutube ? "youtube" : "file"
      wrapper.contentEditable = "false"
      if (node.attrs.width) wrapper.style.width = toCssWidth(node.attrs.width)

      let inner
      if (isYoutube) {
        inner = document.createElement("iframe")
        inner.src = toYoutubeEmbed(node.attrs.src) || node.attrs.src
        inner.setAttribute("frameborder", "0")
        inner.setAttribute("allowfullscreen", "true")
        inner.setAttribute(
          "allow",
          "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        )
        inner.setAttribute("referrerpolicy", "strict-origin-when-cross-origin")
      } else {
        inner = document.createElement("video")
        inner.src = node.attrs.src
        inner.controls = true
        inner.playsInline = true
        inner.preload = "metadata"
        if (node.attrs.title) inner.title = node.attrs.title
      }
      wrapper.appendChild(inner)

      const isEditable = !!editor?.isEditable

      if (isEditable) {
        HANDLES.forEach((pos) => {
          const h = document.createElement("span")
          h.className = `ttx-resize-handle ttx-resize-${pos}`
          h.dataset.handle = pos
          wrapper.appendChild(h)
        })
      }

      const refreshSelected = () => {
        if (!isEditable) return
        const selection = editor.state.selection
        const pos = typeof getPos === "function" ? getPos() : null
        const selected =
          pos !== null && selection.from === pos && selection.to === pos + 1
        wrapper.classList.toggle("is-selected", selected)
      }
      const onSel = () => refreshSelected()
      if (isEditable) {
        editor.on("selectionUpdate", onSel)
        editor.on("transaction", onSel)
        refreshSelected()
      }

      // ---- Pointer drag (proportional resize, same logic as image) ------
      let drag = null

      const onPointerDown = (e) => {
        if (!isEditable) return
        const handle = e.target?.closest?.(".ttx-resize-handle")
        if (!handle) return
        e.preventDefault()
        e.stopPropagation()
        try {
          wrapper.setPointerCapture?.(e.pointerId)
        } catch (_) {
          // Synthetic / replayed pointer events have no captured pointer id;
          // we can fall back to the document listeners below.
        }

        const rect = wrapper.getBoundingClientRect()
        drag = {
          startX: e.clientX,
          startW: rect.width,
          sign: handle.dataset.handle.endsWith("e") ? 1 : -1,
        }
        wrapper.classList.add("is-resizing")
        // Block iframe / video from eating pointermove events while dragging.
        if (inner) inner.style.pointerEvents = "none"
        window.addEventListener("pointermove", onPointerMove)
        window.addEventListener("pointerup", onPointerUp)
        window.addEventListener("pointercancel", onPointerUp)
      }

      const onPointerMove = (e) => {
        if (!drag) return
        const dx = e.clientX - drag.startX
        const w = Math.max(MIN_WIDTH, Math.round(drag.startW + dx * drag.sign))
        wrapper.style.width = `${w}px`
      }

      const onPointerUp = () => {
        window.removeEventListener("pointermove", onPointerMove)
        window.removeEventListener("pointerup", onPointerUp)
        window.removeEventListener("pointercancel", onPointerUp)
        wrapper.classList.remove("is-resizing")
        if (inner) inner.style.pointerEvents = ""
        if (!drag) return

        const finalWidth = parseFloat(wrapper.style.width)
        drag = null
        if (
          typeof getPos === "function" &&
          Number.isFinite(finalWidth) &&
          finalWidth > 0
        ) {
          editor.commands.command(({ tr }) => {
            const pos = getPos()
            if (pos == null) return false
            const current = tr.doc.nodeAt(pos)
            if (!current || current.type.name !== "video") return false
            tr.setNodeMarkup(pos, undefined, {
              ...current.attrs,
              width: Math.round(finalWidth),
            })
            return true
          })
        }
      }

      wrapper.addEventListener("pointerdown", onPointerDown)

      return {
        dom: wrapper,
        ignoreMutation(mutation) {
          if (mutation.type === "attributes" && mutation.target === wrapper) {
            return true
          }
          return false
        },
        update(updatedNode) {
          if (updatedNode.type.name !== "video") return false
          if (updatedNode.attrs.src !== node.attrs.src) {
            if (isYoutube) {
              inner.src = toYoutubeEmbed(updatedNode.attrs.src) || updatedNode.attrs.src
            } else {
              inner.src = updatedNode.attrs.src
            }
          }
          const cssW = toCssWidth(updatedNode.attrs.width)
          if (wrapper.style.width !== cssW) wrapper.style.width = cssW
          return true
        },
        selectNode() {
          wrapper.classList.add("is-selected")
        },
        deselectNode() {
          wrapper.classList.remove("is-selected")
        },
        stopEvent(event) {
          return !!event.target?.closest?.(".ttx-resize-handle")
        },
        destroy() {
          if (isEditable) {
            editor.off("selectionUpdate", onSel)
            editor.off("transaction", onSel)
          }
          wrapper.removeEventListener("pointerdown", onPointerDown)
        },
      }
    }
  },
})
