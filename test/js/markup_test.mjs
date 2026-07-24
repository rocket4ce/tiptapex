// The JS markup renderer must admit exactly what `Tiptapex.Renderer.Markup`
// admits — the editor's running header is a preview of the exported PDF, and
// a subset that differs on either side is a lie or a hole.
import assert from "node:assert/strict"

import "./dom.mjs"
import { test } from "./harness.mjs"
import { renderMarkup, hasMarkup } from "tiptapex/markup"
import { safeUrl, safeImageUrl, safeCssValue } from "tiptapex/url"

const t = (name, fn) => test("markup", name, fn)

// Renders into a detached span and returns its innerHTML — which is the
// browser's serialisation of nodes we built, never a parse of the input.
const html = (text) => renderMarkup(text, document.createElement("div")).innerHTML

t("renders inline and block tags", () => {
  assert.equal(html("<b>a</b><i>b</i><span>c</span>"), "<b>a</b><i>b</i><span>c</span>")
  assert.equal(html("<h1>hola</h1>"), "<h1>hola</h1>")
  assert.equal(html("<p>one</p><div>two</div>"), "<p>one</p><div>two</div>")
})

t("renders void tags with or without the slash", () => {
  assert.equal(html("a<br>b"), "a<br>b")
  assert.equal(html("a<br/>b"), "a<br>b")
})

t("nests, and leaves tokens alone", () => {
  assert.equal(html("<b>bold <i>and italic</i></b>"), "<b>bold <i>and italic</i></b>")
  assert.equal(html("Page {page} of {pages}"), "Page {page} of {pages}")
})

t("an unknown tag becomes visible text, never an element", () => {
  assert.equal(html("<script>alert(1)</script>"), "&lt;script&gt;alert(1)&lt;/script&gt;")
  assert.equal(html("<iframe src=x>"), "&lt;iframe src=x&gt;")

  const target = renderMarkup("<script>alert(1)</script>", document.createElement("div"))
  assert.equal(target.querySelector("script"), null, "no script element is ever created")
})

t("a malformed tag becomes text", () => {
  assert.equal(html('<b onclick=alert(1)>x'), "&lt;b onclick=alert(1)&gt;x")
  assert.equal(html("a < b"), "a &lt; b")
})

t("an event handler on an allowed tag is dropped, the tag survives", () => {
  assert.equal(html('<b onclick="alert(1)">x</b>'), "<b>x</b>")
  assert.equal(html('<span onmouseover="x" style="color: red">y</span>'), '<span style="color: red">y</span>')
})

t("style keeps allow-listed properties and drops the rest", () => {
  assert.equal(
    html('<span style="color: #ff0000; font-weight: bold">x</span>'),
    '<span style="color: #ff0000; font-weight: bold">x</span>'
  )
  assert.equal(html('<span style="position: fixed; color: red">x</span>'), '<span style="color: red">x</span>')
  assert.equal(html('<span style="background-color: url(javascript:alert(1))">x</span>'), "<span>x</span>")
})

t("links are validated and get rel", () => {
  assert.equal(
    html('<a href="https://acme.test">x</a>'),
    '<a href="https://acme.test" rel="noopener nofollow">x</a>'
  )
  assert.equal(html('<a href="javascript:alert(1)">x</a>'), "<a>x</a>")
})

t("images take http(s), relative and data: image sources", () => {
  assert.equal(html('<img src="/logo.png" alt="L" height="20">'), '<img src="/logo.png" alt="L" height="20">')
  assert.equal(html('<img src="data:image/png;base64,iVBOR">'), '<img src="data:image/png;base64,iVBOR">')
  assert.equal(html('<img src="data:text/html;base64,PHN2">'), "<img>")
  assert.equal(html('<img src="javascript:alert(1)">'), "<img>")
})

t("unclosed tags stay open and stray closers are dropped", () => {
  assert.equal(html("<b>bold"), "<b>bold</b>")
  assert.equal(html("<b><i>x"), "<b><i>x</i></b>")
  assert.equal(html("x</b>"), "x")
  assert.equal(html("<b>x</i></b>"), "<b>x</b>")
})

t("hasMarkup matches Tiptapex.Renderer.Markup.markup?/1", () => {
  assert.equal(hasMarkup("<b>x</b>"), true)
  assert.equal(hasMarkup("a<br>b"), true)
  assert.equal(hasMarkup("plain"), false)
  assert.equal(hasMarkup("a < b"), false)
  assert.equal(hasMarkup("<script>x</script>"), false)
  assert.equal(hasMarkup(null), false)
})

t("the URL allow-lists mirror Tiptapex.Renderer.URL", () => {
  assert.equal(safeUrl("https://a.test/x"), "https://a.test/x")
  assert.equal(safeUrl("/relative"), "/relative")
  assert.equal(safeUrl("mailto:a@b.test"), "mailto:a@b.test")
  assert.equal(safeUrl("javascript:alert(1)"), null)
  assert.equal(safeUrl("data:image/png;base64,x"), null, "data: is not a link scheme")

  assert.equal(safeImageUrl("data:image/png;base64,x"), "data:image/png;base64,x")
  assert.equal(safeImageUrl("data:text/html;base64,x"), null)
  assert.equal(safeImageUrl("/logo.png"), "/logo.png")

  assert.equal(safeCssValue("#ff0000"), "#ff0000")
  assert.equal(safeCssValue("rgb(1, 2, 3)"), "rgb(1, 2, 3)")
  assert.equal(safeCssValue('red; background: url("x")'), null)
  assert.equal(safeCssValue("x".repeat(101)), null)
})
