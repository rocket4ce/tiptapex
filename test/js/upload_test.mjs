// Upload wiring against a real editor under jsdom: what reaches the document
// when files are pasted, and what the host hears about each upload. `fetch`
// is stubbed per check; no request leaves the process.
import assert from "node:assert/strict"

import { dom } from "./dom.mjs"
import { test } from "./harness.mjs"

const { Editor } = await import("@tiptap/core")
const { TiptapexHook, buildExtensions, uploadAndInsert, uploadFile } = await import("tiptapex")

const UPLOAD = { url: "/uploads", scopeName: null, scopeValue: "", csrfToken: "t" }

function editor(upload = UPLOAD) {
  const element = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(element)

  return new Editor({
    element,
    content: { type: "doc", content: [{ type: "paragraph" }] },
    extensions: buildExtensions({
      dragHandle: false,
      page: false,
      onUploadFiles: (e, files, pos) => uploadAndInsert(e, files, pos, upload),
    }),
  })
}

// Checks run side by side and each one replaces the stub, so every restore
// goes back to the real fetch rather than to whichever stub came before.
const NATIVE_FETCH = globalThis.fetch

function stubFetch(respond) {
  globalThis.fetch = async (...args) => respond(...args)
  return () => (globalThis.fetch = NATIVE_FETCH)
}

const json = (status, body) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => body,
})

// ProseMirror's own paste handler, fed the clipboard a browser hands it.
function paste(e, { files, html, text = "" }) {
  const event = new dom.window.Event("paste", { bubbles: true, cancelable: true })
  event.clipboardData = {
    files,
    types: html ? ["Files", "text/html", "text/plain"] : ["Files"],
    getData: (type) => (type === "text/html" ? html : type === "text/plain" ? text : ""),
  }
  e.view.dom.dispatchEvent(event)
}

const imageSources = (e) => {
  const sources = []
  e.state.doc.descendants((node) => {
    if (node.type.name === "image") sources.push(node.attrs.src)
  })
  return sources
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 30))
const png = () => new File(["png"], "photo.png", { type: "image/png" })

const t = (name, fn) => test("uploads (jsdom)", name, fn)

t("a paste whose HTML has text keeps the HTML and skips the picture beside it", async () => {
  // Word, Excel and some browsers put a rendering of the copied content on
  // the clipboard next to its HTML. Uploading it inserted a picture of the
  // very text that was pasted.
  let uploads = 0
  const restore = stubFetch(() => {
    uploads++
    return json(200, { url: "/uploads/render.png", content_type: "image/png", filename: "render.png" })
  })
  const e = editor()
  try {
    paste(e, { files: [png()], html: '<meta charset="utf-8"><img src="https://example.com/photo.png"><p>Caption</p>' })
    await tick()

    assert.equal(uploads, 0)
    assert.deepEqual(imageSources(e), ["https://example.com/photo.png"])
    assert.match(e.getText(), /Caption/)
  } finally {
    e.destroy()
    restore()
  }
})

t("a copied image is uploaded once and its HTML copy left out", async () => {
  let uploads = 0
  const restore = stubFetch(() => {
    uploads++
    return json(200, { url: "/uploads/photo.png", content_type: "image/png", filename: "photo.png" })
  })
  const e = editor()
  try {
    paste(e, { files: [png()], html: '<meta charset="utf-8"><img src="https://example.com/photo.png">' })
    await tick()

    assert.equal(uploads, 1)
    assert.deepEqual(imageSources(e), ["/uploads/photo.png"])
  } finally {
    e.destroy()
    restore()
  }
})

t("an image-only paste is told apart from text by what renders", async () => {
  const restore = stubFetch(() =>
    json(200, { url: "/uploads/photo.png", content_type: "image/png", filename: "photo.png" })
  )
  const e = editor()
  try {
    paste(e, {
      files: [png()],
      html: '<img src="https://example.com/photo.png"><style>p { color: red }</style><p>\u200b</p>',
    })
    await tick()

    assert.deepEqual(imageSources(e), ["/uploads/photo.png"])
  } finally {
    e.destroy()
    restore()
  }
})

t("inside a code block a paste with a picture beside it stays plain text", async () => {
  let uploads = 0
  const restore = stubFetch(() => {
    uploads++
    return json(200, { url: "/uploads/render.png", content_type: "image/png", filename: "render.png" })
  })
  const e = editor()
  try {
    e.commands.setContent({ type: "doc", content: [{ type: "codeBlock" }] })
    e.commands.setTextSelection(1)
    paste(e, { files: [png()], html: "<p><b>let</b> x = 1</p>", text: "let x = 1" })
    await tick()

    assert.equal(uploads, 0)
    const code = e.state.doc.firstChild
    assert.equal(code.type.name, "codeBlock")
    assert.equal(code.textContent, "let x = 1")
  } finally {
    e.destroy()
    restore()
  }
})

// What a host hears about one upload: `onStart` before the request, `onError`
// with the HTTP status and the endpoint's `{error}` code when there is one.
async function failedUpload(respond, upload = UPLOAD) {
  const heard = { started: [], errors: [] }
  const restore = stubFetch(respond)
  try {
    const result = await uploadFile(png(), {
      ...upload,
      onStart: (file) => heard.started.push(file.name),
      onError: (file, info) => heard.errors.push({ filename: file.name, ...info }),
    }).catch((error) => ({ thrown: error }))
    return { ...heard, result }
  } finally {
    restore()
  }
}

t("a rejected upload reports its status and error code", async () => {
  const { started, errors, result } = await failedUpload(() => json(422, { error: "too_large" }))

  assert.deepEqual(started, ["photo.png"])
  assert.deepEqual(errors, [{ filename: "photo.png", status: 422, error: "too_large" }])
  assert.ok(result.thrown, "callers still see the failure")
})

t("an upload refused before the app (HTML body) reports the status alone", async () => {
  const { errors } = await failedUpload(() => ({
    ok: false,
    status: 413,
    json: async () => JSON.parse("<html>"),
  }))

  assert.deepEqual(errors, [{ filename: "photo.png", status: 413, error: null }])
})

t("a success answer that is not JSON is reported as a failure", async () => {
  const { started, errors } = await failedUpload(() => ({
    ok: true,
    status: 200,
    json: async () => JSON.parse("<html>"),
  }))

  assert.deepEqual(started, ["photo.png"])
  assert.deepEqual(errors, [{ filename: "photo.png", status: 200, error: null }])
})

t("an upload that never reaches the server reports no status", async () => {
  const { errors } = await failedUpload(() => Promise.reject(new TypeError("Failed to fetch")))

  assert.deepEqual(errors, [{ filename: "photo.png", status: null, error: null }])
})

t("an upload blocked for want of a scope says so instead of failing silently", async () => {
  const { started, errors, result } = await failedUpload(() => assert.fail("no request expected"), {
    ...UPLOAD,
    scopeName: "scope",
    scopeValue: "",
  })

  assert.deepEqual(started, [])
  assert.deepEqual(errors, [{ filename: "photo.png", status: null, error: "no_scope" }])
  assert.equal(result, null)
})

t("a file over the size limit is refused before it is sent", async () => {
  // Proxies that buffer the request body (Cloudflare does) hold the server's
  // answer until the whole file has gone up; checking here answers at once.
  const { started, errors, result } = await failedUpload(() => assert.fail("no request expected"), {
    ...UPLOAD,
    maxBytes: 2,
  })

  assert.deepEqual(started, [])
  assert.deepEqual(errors, [{ filename: "photo.png", status: null, error: "too_large" }])
  assert.equal(result, null)
})

t("a file of exactly the size limit is still sent", async () => {
  const { started } = await failedUpload(() => json(422, { error: "x" }), { ...UPLOAD, maxBytes: 3 })

  assert.deepEqual(started, ["photo.png"])
})

t("the hook pushes the opt-in start and error events to the LiveView", async () => {
  const el = dom.window.document.createElement("div")
  el.id = "ed"
  el.dataset.ttxUploadUrl = "/uploads"
  el.dataset.ttxEventUploadStart = "upload_started"
  el.dataset.ttxEventUploadError = "upload_failed"
  el.innerHTML = '<div data-ttx-role="editor"></div>'
  dom.window.document.body.appendChild(el)

  const pushed = []
  const hook = {
    ...TiptapexHook,
    el,
    pushEventTo: (_target, event, payload) => pushed.push([event, payload]),
    handleEvent: () => {},
  }
  const restore = stubFetch(() => json(422, { error: "too_large" }))
  try {
    hook.mounted()
    // The request goes out before the first await, while this stub is in
    // place: the harness runs async checks side by side.
    paste(hook.editor, { files: [png()], html: "" })
    await tick()

    assert.deepEqual(
      pushed.filter(([event]) => event.startsWith("upload_")),
      [
        ["upload_started", { filename: "photo.png" }],
        ["upload_failed", { filename: "photo.png", status: 422, error: "too_large" }],
      ]
    )
  } finally {
    hook.destroyed?.()
    restore()
  }
})

t("a file over the size limit does not stop the files after it", async () => {
  const big = new File(["too large"], "big.png", { type: "image/png" })
  const heard = { started: [], errors: [] }
  const e = editor()
  const restore = stubFetch(() => json(200, { url: "/u/photo.png", content_type: "image/png", filename: "photo.png" }))
  try {
    await uploadAndInsert(e, [big, png()], null, {
      ...UPLOAD,
      maxBytes: 3,
      onStart: (file) => heard.started.push(file.name),
      onError: (file, info) => heard.errors.push({ filename: file.name, ...info }),
    })

    assert.deepEqual(heard.errors[0], { filename: "big.png", status: null, error: "too_large" })
    // Started is the point: the second request goes out after an await, when
    // a check running alongside may have swapped the fetch stub.
    assert.deepEqual(heard.started, ["photo.png"])
  } finally {
    restore()
    e.destroy()
  }
})

t("the hook reads the size limit from the element", async () => {
  const el = dom.window.document.createElement("div")
  el.id = "ed-limit"
  el.dataset.ttxUploadUrl = "/uploads"
  el.dataset.ttxUploadMaxBytes = "2"
  el.dataset.ttxEventUploadError = "upload_failed"
  el.innerHTML = '<div data-ttx-role="editor"></div>'
  dom.window.document.body.appendChild(el)

  const pushed = []
  const hook = {
    ...TiptapexHook,
    el,
    pushEventTo: (_target, event, payload) => pushed.push([event, payload]),
    handleEvent: () => {},
  }
  const restore = stubFetch(() => assert.fail("no request expected"))
  try {
    hook.mounted()
    paste(hook.editor, { files: [png()], html: "" })
    await tick()

    assert.deepEqual(
      pushed.filter(([event]) => event.startsWith("upload_")),
      [["upload_failed", { filename: "photo.png", status: null, error: "too_large" }]]
    )
  } finally {
    hook.destroyed?.()
    restore()
  }
})
