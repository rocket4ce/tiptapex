// Vanilla resizable-image extension on top of `@tiptap/extension-image`.
//
// What it adds on top of the default Image node:
//
// - A `width` attribute persisted to ProseMirror JSON and rendered as the
//   `width` HTML attribute, so the size survives saves and round-trips
//   through the server-side renderer and the read-only viewer.
// - A NodeView (vanilla DOM) that wraps the `<img>` in a `<span>` and draws
//   four corner handles when the image is selected.
// - Proportional resize only: we drag a corner, compute the new width from
//   the cursor delta, and let CSS keep `height: auto`. No skew possible.
import { Image } from "@tiptap/extension-image"

const MIN_WIDTH = 40
const HANDLES = ["nw", "ne", "sw", "se"]

function toCssWidth(value) {
  if (value === null || value === undefined || value === "") return ""
  if (typeof value === "number") return `${value}px`
  return /^\d+(\.\d+)?$/.test(String(value)) ? `${value}px` : String(value)
}

export const ResizableImage = Image.extend({
  name: "image",

  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (el) => {
          const attr = el.getAttribute("width")
          if (attr) return parseInt(attr, 10) || attr
          const style = el.style?.width
          if (style) return parseInt(style, 10) || style
          return null
        },
        renderHTML: (attrs) => {
          if (!attrs.width) return {}
          return {
            width: typeof attrs.width === "number" ? attrs.width : attrs.width,
            style: `width: ${toCssWidth(attrs.width)}; height: auto;`,
          }
        },
      },
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      const wrapper = document.createElement("span")
      wrapper.className = "ttx-resize-wrapper"
      wrapper.contentEditable = "false"
      if (node.attrs.width) wrapper.style.width = toCssWidth(node.attrs.width)

      const img = document.createElement("img")
      img.src = node.attrs.src
      img.alt = node.attrs.alt || ""
      if (node.attrs.title) img.title = node.attrs.title
      img.draggable = false
      wrapper.appendChild(img)

      // Don't paint handles when the editor is read-only (viewer mounts).
      const isEditable = !!editor?.isEditable

      if (isEditable) {
        HANDLES.forEach((pos) => {
          const h = document.createElement("span")
          h.className = `ttx-resize-handle ttx-resize-${pos}`
          h.dataset.handle = pos
          wrapper.appendChild(h)
        })
      }

      // Selection state — show handles only when the image node is selected.
      const refreshSelected = () => {
        if (!isEditable) return
        const selection = editor.state.selection
        const pos = typeof getPos === "function" ? getPos() : null
        const selected =
          pos !== null &&
          selection.from === pos &&
          selection.to === pos + 1 // NodeSelection covers one position
        wrapper.classList.toggle("is-selected", selected)
      }

      const selectionListener = () => refreshSelected()
      if (isEditable) {
        editor.on("selectionUpdate", selectionListener)
        editor.on("transaction", selectionListener)
        refreshSelected()
      }

      // ---- Pointer drag --------------------------------------------------
      let drag = null

      const onPointerDown = (e) => {
        if (!isEditable) return
        const handle = e.target?.closest?.(".ttx-resize-handle")
        if (!handle) return
        e.preventDefault()
        e.stopPropagation()
        try {
          wrapper.setPointerCapture?.(e.pointerId)
        } catch (_) {}

        const rect = img.getBoundingClientRect()
        drag = {
          startX: e.clientX,
          startW: rect.width,
          aspect: rect.width / Math.max(rect.height, 1),
          // For east handles (ne, se), dragging right grows width. For west
          // (nw, sw), dragging right SHRINKS width.
          sign: handle.dataset.handle.endsWith("e") ? 1 : -1,
          pointerId: e.pointerId,
        }
        wrapper.classList.add("is-resizing")
        document.body.style.cursor =
          handle.dataset.handle === "ne" || handle.dataset.handle === "sw"
            ? "nesw-resize"
            : "nwse-resize"
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
        document.body.style.cursor = ""
        wrapper.classList.remove("is-resizing")
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
            if (!current || current.type.name !== "image") return false
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
        // No content inside an image node.
        ignoreMutation(mutation) {
          // Mutation observer would otherwise fire on every width style change.
          if (mutation.type === "attributes" && mutation.target === wrapper) {
            return true
          }
          return false
        },
        update(updatedNode) {
          if (updatedNode.type.name !== "image") return false
          if (updatedNode.attrs.src !== img.src) img.src = updatedNode.attrs.src
          if (updatedNode.attrs.alt !== img.alt) img.alt = updatedNode.attrs.alt || ""
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
        // Let the handles eat their own pointer events.
        stopEvent(event) {
          return !!event.target?.closest?.(".ttx-resize-handle")
        },
        destroy() {
          if (isEditable) {
            editor.off("selectionUpdate", selectionListener)
            editor.off("transaction", selectionListener)
          }
          wrapper.removeEventListener("pointerdown", onPointerDown)
        },
      }
    }
  },
})
