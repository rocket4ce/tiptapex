// Tiptap editor wired up as a Phoenix LiveView Hook.
//
// The hook lives on the root element rendered by `<.tiptapex_editor>` and
// mounts a Tiptap instance with the full extension matrix. On every document
// change (debounced) it either pushes the configured change event to the
// LiveView with `{json, html, characters}`, or writes the JSON into a hidden
// form input — depending on the component's `sync` mode.
//
// File uploads (drag/drop, paste, toolbar button) are POSTed to the
// configured upload URL and the returned URL is inserted as an image, video
// node, or download link.
//
// All configuration arrives via `data-ttx-*` attributes; see readOpts()
// below for the full list. Hosts needing JS-level configuration (custom
// extensions, extra toolbar buttons, collaboration) use `makeEditorHook`.
import { Editor } from "@tiptap/core"
import { StarterKit } from "@tiptap/starter-kit"
import { BubbleMenu } from "@tiptap/extension-bubble-menu"
import { CharacterCount } from "@tiptap/extension-character-count"
import { Color } from "@tiptap/extension-color"
import { DragHandle } from "@tiptap/extension-drag-handle"
import { Dropcursor } from "@tiptap/extension-dropcursor"
import { FileHandler } from "@tiptap/extension-file-handler"
import { FloatingMenu } from "@tiptap/extension-floating-menu"
import { Focus } from "@tiptap/extension-focus"
import { FontFamily } from "@tiptap/extension-font-family"
import { Gapcursor } from "@tiptap/extension-gapcursor"
import { Highlight } from "@tiptap/extension-highlight"
import { InvisibleCharacters } from "@tiptap/extension-invisible-characters"
import { Link } from "@tiptap/extension-link"
import { TaskList, TaskItem } from "@tiptap/extension-list"
import { ListKeymap } from "@tiptap/extension-list-keymap"
import { Placeholder } from "@tiptap/extension-placeholder"
import { Table, TableCell, TableHeader, TableRow } from "@tiptap/extension-table"
import { TableOfContents } from "@tiptap/extension-table-of-contents"
import { TextAlign } from "@tiptap/extension-text-align"
import { TextStyle } from "@tiptap/extension-text-style"
import { Typography } from "@tiptap/extension-typography"
import { UniqueID } from "@tiptap/extension-unique-id"

import { ResizableImage } from "./extensions/resizable-image"
import { Video } from "./extensions/video"
import { LineHeight } from "./extensions/line-height"
import { FontSize } from "./extensions/font-size"
import { BackgroundColor } from "./extensions/background-color"
import { TrailingNode } from "./extensions/trailing-node"
import { SelectionPreserve } from "./extensions/selection-preserve"

import { buildToolbar } from "./toolbar"
import { attachTableMenu } from "./table-menu"
import { attachHtmlView } from "./html-view"
import { DEFAULTS, EMPTY_DOC, ATTACHMENT_MIME, parseJSON, csrfToken } from "./config"

export const DEFAULT_UPLOAD_MIME_TYPES = [
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "video/mp4",
  "video/webm",
  "application/pdf",
]

// Assembles the extension list. Every feature is gated by `opts` so hosts
// can switch pieces off; `opts.extend` gets the final say.
export function buildExtensions(opts = {}) {
  const {
    placeholder = DEFAULTS.placeholder,
    characterCountLimit = 50_000,
    table = true,
    tableOfContents = true,
    invisibleChars = true,
    dragHandle = true,
    dragHandleLabel = "Drag to move",
    link = true,
    typography = true,
    taskList = true,
    onUploadFiles = null,
    uploadMimeTypes = DEFAULT_UPLOAD_MIME_TYPES,
    collabExtensions = [],
    extend = null,
  } = opts

  // Collaboration manages history itself — disable StarterKit's local undo
  // (named `undoRedo` since Tiptap v3) so the two systems don't fight.
  const history = collabExtensions.length > 0 ? false : true

  const exts = [
    StarterKit.configure({
      undoRedo: history ? undefined : false,
      // StarterKit v3 bundles these; we provide our own (configured or
      // custom) versions below, so switch the built-ins off to avoid
      // duplicate-extension conflicts.
      link: false,
      listKeymap: false,
      dropcursor: false,
      gapcursor: false,
      trailingNode: false,
    }),
    Placeholder.configure({ placeholder }),
    BubbleMenu,
    FloatingMenu,
    Focus.configure({ className: "is-focused", mode: "all" }),
    Color,
    BackgroundColor,
    TextStyle,
    FontFamily.configure({ types: ["textStyle"] }),
    FontSize,
    LineHeight,
    TextAlign.configure({ types: ["heading", "paragraph"] }),
    Highlight.configure({ multicolor: true }),
    ResizableImage.configure({ inline: false, allowBase64: false }),
    link &&
      Link.configure({
        openOnClick: false,
        autolink: true,
        HTMLAttributes: { rel: "noopener nofollow" },
      }),
    taskList && TaskList,
    taskList && TaskItem.configure({ nested: true }),
    ListKeymap,
    table && Table.configure({ resizable: true }),
    table && TableRow,
    table && TableHeader,
    table && TableCell,
    tableOfContents && TableOfContents,
    typography && Typography,
    Dropcursor,
    Gapcursor,
    CharacterCount.configure({ limit: characterCountLimit }),
    // Off by default — paragraph marks (¶) appear cluttered when editing.
    // The toolbar's pilcrow button toggles them on demand.
    invisibleChars && InvisibleCharacters.configure({ visible: false }),
    dragHandle &&
      DragHandle.configure({
        // Allow grabbing nested blocks (list items, blockquotes, …) not only
        // top-level.
        nested: true,
        // Provide a richer handle with a 6-dot icon. CSS handles the
        // visuals; we mark it draggable so the browser's HTML5 DnD kicks in.
        render: () => {
          const el = document.createElement("div")
          el.classList.add("ttx-drag-handle")
          el.setAttribute("draggable", "true")
          el.setAttribute("aria-label", dragHandleLabel)
          el.setAttribute("title", dragHandleLabel)
          return el
        },
      }),
    TrailingNode,
    UniqueID.configure({ types: ["heading", "paragraph", "blockquote"] }),
    SelectionPreserve,
    onUploadFiles &&
      FileHandler.configure({
        allowedMimeTypes: uploadMimeTypes,
        onDrop: (currentEditor, files, pos) => onUploadFiles(currentEditor, files, pos),
        onPaste: (currentEditor, files) => onUploadFiles(currentEditor, files, null),
      }),
    Video,
    ...collabExtensions,
  ].filter(Boolean)

  return typeof extend === "function" ? extend(exts) : exts
}

// Uploads each file to `upload.url` as multipart form data and inserts the
// result into the doc: image for image/*, a video node for video/*, and a
// download link for everything else.
//
// Upload payload contract (frozen):
//   request:  multipart "file" + optional "<scopeName>" field,
//             header "x-csrf-token"
//   response: {"url": ..., "content_type": ..., "filename": ...}
export async function uploadAndInsert(editor, files, pos, upload) {
  if (upload.scopeName != null && !upload.scopeValue) {
    console.warn(
      "[Tiptapex] Cannot upload: no upload scope yet (save the record first)."
    )
    return
  }

  for (const file of files) {
    try {
      const form = new FormData()
      form.append("file", file)
      if (upload.scopeName != null) form.append(upload.scopeName, upload.scopeValue)
      const resp = await fetch(upload.url, {
        method: "POST",
        body: form,
        headers: { "x-csrf-token": upload.csrfToken },
        credentials: "same-origin",
      })
      if (!resp.ok) throw new Error("Upload failed: " + resp.status)
      const { url, content_type, filename } = await resp.json()
      const cmd = editor.chain().focus()
      if (pos != null) cmd.setTextSelection(pos)
      if (content_type && content_type.startsWith("image/")) {
        cmd.setImage({ src: url, alt: filename }).run()
      } else if (content_type && content_type.startsWith("video/")) {
        cmd
          .insertContent({
            type: "video",
            attrs: { src: url, kind: "file", title: filename },
          })
          .run()
      } else {
        cmd
          .setLink({ href: url })
          .insertContent(filename)
          .unsetLink()
          .insertContent(" ")
          .run()
      }
      // Tell the LiveView (e.g. so an attachments sidebar can refresh).
      upload.onUploaded?.()
    } catch (e) {
      console.error("[Tiptapex] upload error", e)
    }
  }
}

function readOpts(el) {
  const d = el.dataset
  return {
    doc: parseJSON(d.ttxDoc, EMPTY_DOC),
    uploadUrl: d.ttxUploadUrl || null,
    uploadScopeName: "ttxUploadScopeName" in d ? d.ttxUploadScopeName || DEFAULTS.uploadScopeName : null,
    uploadScopeValue: d.ttxUploadScope || "",
    changeEvent: "ttxEventChange" in d ? d.ttxEventChange : DEFAULTS.changeEvent,
    uploadedEvent: "ttxEventUploaded" in d ? d.ttxEventUploaded : DEFAULTS.uploadedEvent,
    setContentEvent: d.ttxSetContentEvent || (el.id ? `tiptapex:set-content:${el.id}` : null),
    inputId: d.ttxInputId || null,
    placeholder: d.ttxPlaceholder || DEFAULTS.placeholder,
    debounceMs: parseInt(d.ttxDebounce || "", 10) || DEFAULTS.debounceMs,
    countTemplate: d.ttxCountTemplate || DEFAULTS.countTemplate,
    collabTopic: d.ttxCollabTopic || null,
    collabSocketPath: d.ttxCollabSocketPath || DEFAULTS.socketPath,
    collabUser: parseJSON(d.ttxCollabUser),
    toolbar: parseJSON(d.ttxToolbar),
    extensions: parseJSON(d.ttxExtensions, {}),
    labels: parseJSON(d.ttxLabels, {}),
  }
}

// Builds a LiveView hook object. `staticOpts` carries everything that can't
// be expressed as data attributes:
//
//   makeEditorHook({
//     collab: CollabPlugin,            // from "tiptapex/collaboration"
//     htmlEditor: CodeMirrorHtmlEditor, // from "tiptapex/html-editor"
//     extend: (extensions) => [...],   // add/replace Tiptap extensions
//     toolbar: { custom: [...] },      // extra toolbar config (merged)
//   })
export function makeEditorHook(staticOpts = {}) {
  return {
    mounted() {
      const el = this.el
      const target = el.querySelector("[data-ttx-role='editor']") || el
      const toolbarEl = el.querySelector("[data-ttx-role='toolbar']")
      const counter = el.querySelector("[data-ttx-role='char-count']")
      const opts = readOpts(el)
      const token = csrfToken()

      // ---- Realtime collaboration (optional) -------------------
      let collab = null
      let collabExtensions = []
      if (opts.collabTopic) {
        if (staticOpts.collab) {
          collab = staticOpts.collab.create({
            topic: opts.collabTopic,
            socketPath: opts.collabSocketPath,
            user: opts.collabUser,
            csrfToken: token,
          })
          collabExtensions = staticOpts.collab.extensions(collab)
          this.collab = collab
          this._collabPlugin = staticOpts.collab
        } else {
          console.warn(
            "[Tiptapex] collab topic set but the hook has no collab plugin. " +
              'Build the hook with makeEditorHook({ collab: CollabPlugin }) — ' +
              'import { CollabPlugin } from "tiptapex/collaboration".'
          )
        }
      }

      // ---- Uploads ---------------------------------------------
      let upload = null
      if (opts.uploadUrl) {
        upload = {
          url: opts.uploadUrl,
          scopeName: opts.uploadScopeName,
          scopeValue: opts.uploadScopeValue,
          csrfToken: token,
          onUploaded: () => {
            if (opts.uploadedEvent) this.pushEventTo(el, opts.uploadedEvent, {})
          },
        }
      }
      const onUploadFiles = upload
        ? (editor, files, pos) => uploadAndInsert(editor, files, pos, upload)
        : null

      const extensionOpts = {
        placeholder: opts.placeholder,
        ...opts.extensions,
        collabExtensions,
        onUploadFiles,
        extend: staticOpts.extend,
      }

      const buildExts = staticOpts.buildExtensions || buildExtensions

      this.editor = new Editor({
        element: target,
        // When collaborating, Yjs is the source of truth — never seed content
        // ourselves or we'd duplicate the doc.
        content: collab ? undefined : opts.doc,
        autofocus: false,
        extensions: buildExts(extensionOpts),
      })

      // Programmatic access for host JS (tests, custom buttons, …).
      el.tiptapexEditor = this.editor

      // With collaboration active, content replacement must go through the
      // Y.Doc — a plain setContent gets reverted when the sync plugin
      // re-renders from the Y.Doc.
      const applyContent = (json) => {
        if (collab && staticOpts.collab?.setContent) {
          staticOpts.collab.setContent(collab, this.editor, json)
        } else {
          this.editor.commands.setContent(json)
        }
        // Keep the HTML source view (if showing) in step so a stale
        // textarea doesn't overwrite the pushed content on the next edit.
        this._htmlView?.refresh()
      }

      // First user to enter a collaborative room seeds the Y.Doc with the
      // existing content. We wait a beat so peers (if any) have time to send
      // us their state first.
      if (collab) {
        this._seedTimer = setTimeout(() => {
          const docEmpty = this.editor.state.doc.textContent === ""
          if (docEmpty && opts.doc && opts.doc.content) {
            applyContent(opts.doc)
          }
        }, 800)
      }

      // ---- Editable HTML source view (optional) ----------------
      // Under collaboration the parsed document is applied through the
      // Y.Doc (a plain setContent gets reverted by the sync plugin), so the
      // view needs a collab plugin that supports setContent.
      if (opts.extensions.htmlView !== false && (!collab || staticOpts.collab?.setContent)) {
        this._htmlView = attachHtmlView(this.editor, el, {
          debounceMs: opts.debounceMs,
          codeEditor: staticOpts.htmlEditor || null,
          applyJSON: collab
            ? (json) => staticOpts.collab.setContent(collab, this.editor, json)
            : null,
        })
        el.tiptapexHtmlView = this._htmlView
      }

      if (toolbarEl && opts.toolbar !== false) {
        try {
          const toolbarConfig = Array.isArray(opts.toolbar)
            ? { groups: opts.toolbar }
            : opts.toolbar || {}
          buildToolbar(this.editor, toolbarEl, {
            ...toolbarConfig,
            ...(staticOpts.toolbar || {}),
            htmlView: this._htmlView,
            labels: { ...(toolbarConfig.labels || {}), ...opts.labels },
            uploadFiles: onUploadFiles
              ? (files, pos) => onUploadFiles(this.editor, files, pos)
              : undefined,
          })
        } catch (e) {
          console.error("[Tiptapex] toolbar build failed:", e.message, e.stack)
        }
      }

      // Floating table menu — only mounted in editable mode and only visible
      // when the selection is inside a `<table>`.
      if (opts.extensions.table !== false) {
        try {
          this._detachTableMenu = attachTableMenu(this.editor, el, opts.labels)
        } catch (e) {
          console.error("[Tiptapex] table menu attach failed:", e.message)
        }
      }

      const updateCount = () => {
        if (!counter) return
        const chars = this.editor.storage.characterCount.characters()
        const words = this.editor.storage.characterCount.words()
        counter.textContent = opts.countTemplate
          .replace("{chars}", chars)
          .replace("{words}", words)
      }
      updateCount()

      const inputEl = opts.inputId ? document.getElementById(opts.inputId) : null

      let debounce
      this.editor.on("update", () => {
        updateCount()
        clearTimeout(debounce)
        debounce = setTimeout(() => {
          const json = this.editor.getJSON()
          if (inputEl) {
            // Hidden-input sync: write the doc into the form field and let
            // the surrounding form's phx-change pick it up.
            inputEl.value = JSON.stringify(json)
            inputEl.dispatchEvent(new Event("input", { bubbles: true }))
          }
          if (opts.changeEvent) {
            this.pushEventTo(el, opts.changeEvent, {
              json,
              html: this.editor.getHTML(),
              characters: this.editor.storage.characterCount.characters(),
            })
          }
        }, opts.debounceMs)
      })
      this._debounceTimer = () => clearTimeout(debounce)

      // Allow external commands from the LiveView, namespaced per editor id
      // so several editors can coexist in one view.
      if (opts.setContentEvent) {
        this.handleEvent(opts.setContentEvent, ({ json }) => {
          if (json) applyContent(json)
        })
      }

      // Escape hatch: host JS can dispatch this bubbling CustomEvent to
      // trigger the uploaded notification (e.g. after its own upload flow).
      this._onUploadedHandler = () => {
        if (opts.uploadedEvent) this.pushEventTo(el, opts.uploadedEvent, {})
      }
      el.addEventListener("tiptapex:uploaded", this._onUploadedHandler)

      // ---- Drag & drop existing attachments → editor ---------------
      this._installAttachmentDnD(target)
    },

    // Hosts can render existing attachments as `<li draggable="true"
    // data-ttx-attachment="{json}">` anywhere on the page. We listen at the
    // document level for dragstart so even items rendered later by the
    // LiveView pick this up. On the ProseMirror target we capture drop and
    // use `view.posAtCoords` to insert at the cursor's exact position,
    // matching the visual drop indicator the user expects.
    _installAttachmentDnD(target) {
      const editor = this.editor

      this._attachDragStart = (e) => {
        const li = e.target.closest("[data-ttx-attachment]")
        if (!li) return
        try {
          const payload = li.getAttribute("data-ttx-attachment")
          e.dataTransfer.setData(ATTACHMENT_MIME, payload)
          e.dataTransfer.setData("text/plain", JSON.parse(payload).filename || "")
          e.dataTransfer.effectAllowed = "copy"
        } catch (err) {
          console.error("[Tiptapex] bad attachment payload", err)
        }
      }
      document.addEventListener("dragstart", this._attachDragStart)

      this._attachDragOver = (e) => {
        // Only intercept when the drag is one of OUR attachments. Files
        // (from the OS) keep their existing FileHandler path so paste/drop
        // of new images still works.
        if (!Array.from(e.dataTransfer?.types || []).includes(ATTACHMENT_MIME)) return
        e.preventDefault()
        e.dataTransfer.dropEffect = "copy"
        target.classList.add("ttx-drop-active")
      }
      this._attachDragLeave = () => target.classList.remove("ttx-drop-active")
      this._attachDrop = (e) => {
        const raw = e.dataTransfer?.getData(ATTACHMENT_MIME)
        if (!raw) return
        e.preventDefault()
        target.classList.remove("ttx-drop-active")

        let payload
        try {
          payload = JSON.parse(raw)
        } catch (_) {
          return
        }

        // Resolve ProseMirror position from the drop's viewport coordinates.
        const view = editor.view
        const coords = view.posAtCoords({ left: e.clientX, top: e.clientY })
        const pos = coords?.pos ?? editor.state.doc.content.size

        const chain = editor.chain().focus().setTextSelection(pos)

        if ((payload.content_type || "").startsWith("image/")) {
          chain.setImage({ src: payload.url, alt: payload.filename }).run()
        } else if ((payload.content_type || "").startsWith("video/")) {
          chain
            .insertContent({
              type: "video",
              attrs: { src: payload.url, kind: "file", title: payload.filename },
            })
            .run()
        } else {
          chain
            .setLink({ href: payload.url, target: "_blank" })
            .insertContent(payload.filename)
            .unsetLink()
            .insertContent(" ")
            .run()
        }
      }
      target.addEventListener("dragover", this._attachDragOver)
      target.addEventListener("dragleave", this._attachDragLeave)
      target.addEventListener("drop", this._attachDrop)
      this._attachDnDTarget = target
    },

    destroyed() {
      if (this._seedTimer) clearTimeout(this._seedTimer)
      if (this._debounceTimer) this._debounceTimer()
      if (this._detachTableMenu) this._detachTableMenu()
      if (this._htmlView) this._htmlView.destroy()
      if (this._onUploadedHandler) {
        this.el.removeEventListener("tiptapex:uploaded", this._onUploadedHandler)
      }
      if (this._attachDragStart) {
        document.removeEventListener("dragstart", this._attachDragStart)
      }
      if (this._attachDnDTarget) {
        this._attachDnDTarget.removeEventListener("dragover", this._attachDragOver)
        this._attachDnDTarget.removeEventListener("dragleave", this._attachDragLeave)
        this._attachDnDTarget.removeEventListener("drop", this._attachDrop)
      }
      if (this.collab && this._collabPlugin) {
        this._collabPlugin.destroy(this.collab)
      }
      if (this.editor) this.editor.destroy()
    },
  }
}

// The default hook: everything data-attribute-driven, no collaboration
// plugin (collab needs the optional yjs peers — see "tiptapex/collaboration").
export const TiptapexHook = makeEditorHook()
