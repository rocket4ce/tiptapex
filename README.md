# Tiptapex

**[Tiptap](https://tiptap.dev) v3 rich-text editing for Phoenix LiveView (Phoenix ≥ 1.8, LiveView ≥ 1.1).**

Tiptapex packages a production-grade editor integration as a single Hex package:

- **`<.tiptapex_editor>` / `<.tiptapex_viewer>`** — HEEx function components backed by JS hooks shipped inside this package.
- **A full-featured editor** — toolbar (marks, headings, alignment, lists, fonts, colors), resizable images and videos (file + YouTube embeds), tables with a floating context menu, task lists, drag-handle block reordering, placeholder, character count, invisible characters, editable HTML source view.
- **Page layout & PDF** — paper sizes (Letter, Legal, A4…), orientation, margins, running headers/footers with left/centre/right page numbering, forced page breaks, a **live paginated canvas** in the editor, and ready-made options for **`chromic_pdf`** and **`pdf_generator`**.
- **`Tiptapex.Renderer`** — converts the Tiptap/ProseMirror JSON document to **safe, escaped HTML on the server**. No `raw/1`, no trusting client-generated HTML, no stored-XSS surface.
- **Uploads** — a `Tiptapex.Upload` behaviour + controller macro with real server-side validation (size limits and magic-byte content-type sniffing).
- **Realtime collaboration (optional)** — Yjs over Phoenix Channels via `use Tiptapex.Collab.Channel` and a bundled provider; multiple users edit the same doc with live carets.

The canonical storage format is the **JSON document** (an Ecto `:map` / Postgres `jsonb` column). HTML is derived from it on the server whenever you need to display it.

## Installation

### 1. Hex package

```elixir
# mix.exs
def deps do
  [
    {:tiptapex, "~> 0.1.2"}
  ]
end
```

### 2. npm peer dependencies

The JS ships as raw ESM inside the Hex package; your app bundles it with its own copy of Tiptap (this guarantees a single `@tiptap/core` instance):

```bash
cd assets
npm install \
  @tiptap/core @tiptap/pm @tiptap/starter-kit \
  @tiptap/extension-bubble-menu @tiptap/extension-character-count \
  @tiptap/extension-color @tiptap/extension-drag-handle \
  @tiptap/extension-dropcursor @tiptap/extension-file-handler \
  @tiptap/extension-floating-menu @tiptap/extension-focus \
  @tiptap/extension-font-family @tiptap/extension-gapcursor \
  @tiptap/extension-highlight @tiptap/extension-image \
  @tiptap/extension-invisible-characters @tiptap/extension-link \
  @tiptap/extension-list @tiptap/extension-list-keymap \
  @tiptap/extension-placeholder @tiptap/extension-table \
  @tiptap/extension-table-of-contents @tiptap/extension-text-align \
  @tiptap/extension-text-style @tiptap/extension-typography \
  @tiptap/extension-unique-id
```

For collaboration, also:

```bash
npm install @tiptap/extension-collaboration @tiptap/extension-collaboration-caret \
  yjs y-prosemirror y-protocols lib0
```

### 3. esbuild `NODE_PATH`

Tell esbuild to resolve `"tiptapex"` from `deps/` and the Tiptap packages from `assets/node_modules` (imports inside a dep don't reach your `node_modules` on their own):

```elixir
# config/config.exs
config :esbuild,
  my_app: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" =>
        Enum.join(
          [
            Path.expand("../deps", __DIR__),
            Path.expand("../assets/node_modules", __DIR__),
            Mix.Project.build_path()
          ],
          ":"
        )
    }
  ]
```

### 4. Register the hooks

```js
// assets/js/app.js
import { hooks as tiptapex } from "tiptapex"

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, ...tiptapex },
})
```

### 5. Stylesheet

```css
/* assets/css/app.css (Tailwind v4 CSS-first or plain CSS) */
@import "../../deps/tiptapex/priv/static/tiptapex.css";
```

The stylesheet is theme-aware: every color flows through `--ttx-*` custom properties that fall back to daisyUI tokens when present (and to neutral defaults otherwise). Override them to re-skin:

```css
:root { --ttx-primary: #7c3aed; }
```

## Usage

### The editor

```heex
<.tiptapex_editor
  id="article-body"
  value={@body}
  placeholder="Start writing…"
  upload_url={~p"/admin/tiptapex/uploads"}
  upload_scope={@article.id}
  on_change="editor_update"
/>
```

```elixir
def handle_event("editor_update", %{"json" => json, "characters" => chars}, socket) do
  {:noreply, socket |> assign(:body, json) |> assign(:characters, chars) |> assign(:dirty?, true)}
end

def handle_event("save", _params, socket) do
  Articles.update_article(socket.assigns.article, %{body: socket.assigns.body})
  # ...
end
```

Store `body` as `:map` (Postgres `jsonb`) — or use the bundled Ecto type:

```elixir
schema "articles" do
  field :body, Tiptapex.Schema.Document
end
```

#### Form-based sync (no custom events)

For plain changeset forms, bind the editor to a hidden input instead:

```heex
<.form for={@form} phx-change="validate" phx-submit="save">
  <.tiptapex_editor id="body" sync={{:hidden_input, @form[:body]}} />
  <button>Save</button>
</.form>
```

The hook keeps the input in sync with the document JSON and triggers your form's `phx-change`. `Tiptapex.Schema.Document` casts the JSON string automatically.

#### Options worth knowing

| Attr | What it does |
| --- | --- |
| `toolbar={[:marks, :blocks, :lists, :page, :history]}` | ordered subset of groups; `false` hides the toolbar |
| `page={%{size: :letter}}` | paper size, margins, headers/footers, numbering — see [Page layout](#page-layout-and-pdf-export) |
| `extensions={%{table: false, character_count_limit: 10_000}}` | per-feature switches for the JS extension matrix |
| `extensions={%{html_view: false}}` | disables the toolbar's editable HTML source view (`</>` button) |
| `labels={%{bold: "Negrita", insert_link: "Insertar enlace"}}` | i18n for toolbar/table menu (English defaults) |
| `remount_key={@editor_session}` | bump to force a client remount (e.g. after restoring a version) |
| `count_template="{chars} caracteres · {words} palabras · {pages} páginas"` | footer counter format |
| `<:actions>` slot | render buttons in the editor footer |

Push content into a mounted editor from the server (multiple editors are namespaced by id):

```elixir
{:noreply, Tiptapex.Components.set_content(socket, "article-body", restored.body)}

# or change only the page setup, leaving the content alone
{:noreply, Tiptapex.Components.set_page(socket, "article-body", %{orientation: :landscape})}
```

### Displaying documents — the safe way

```heex
<%!-- server-rendered, escaped, allow-listed; no raw/1 anywhere --%>
<.tiptapex_viewer value={@article.body} hydrate={false} />

<%!-- or with client-side hydration (task-list checkboxes etc.) --%>
<.tiptapex_viewer id="article" value={@article.body} />
```

Or call the renderer directly:

```elixir
Tiptapex.Renderer.to_html(doc)          # {:safe, iodata} — interpolate in HEEx
Tiptapex.Renderer.to_plain_text(doc)    # excerpts / search indexing
Tiptapex.Renderer.headings(doc)         # [%{level: 1, id: "…", text: "…"}] for a TOC
```

The renderer covers every node/mark the editor produces and enforces: URL scheme allow-lists (`javascript:`/`data:` stripped), iframes only for canonically rebuilt YouTube embed URLs, a strict CSS value grammar for inline styles, and per-node attribute allow-lists. Unknown nodes are dropped (configurable via `on_unknown:`). Custom nodes plug in via `nodes:`/`marks:` options — see `Tiptapex.Renderer`.

> #### Live preview next to the editor? Pass `ids: false` {: .warning}
>
> When you render the same document on the same page as its live editor
> (e.g. an edit + preview split view), use
> `Tiptapex.Renderer.to_html(@doc, ids: false)`. The editor's DOM carries
> the same heading ids, and LiveView's DOM patcher matches elements by id
> globally — with duplicate ids it will pull nodes out of the editor (even
> inside `phx-update="ignore"`), which ProseMirror then interprets as the
> user deleting them.

### Page layout and PDF export

Give the editor a page setup and it stops being an infinite scroll: it renders
a stack of real sheets, measured as you type, with the running header and
footer drawn in the margins of every page.

```heex
<.tiptapex_editor
  id="contract"
  value={@doc}
  page={%{
    size: :letter,                                   # :letter :legal :a4 :a5 :tabloid :executive
    orientation: :portrait,                          # or :landscape
    margins: %{top: "1in", right: 20, bottom: 20, left: "1in"},
    header: %{left: "Acme S.A.", center: "", right: "{date}"},
    footer: %{left: "", center: "", right: ""},
    numbering: %{enabled: true, region: :footer, align: :center, format: "{page} of {pages}"}
  }}
/>
```

Lengths are millimetres; strings may carry a unit (`"1in"`, `"2cm"`, `"72pt"`,
`"96px"`). Header/footer slots accept the tokens `{page}`, `{pages}`,
`{date}`, `{time}` and `{title}` — put `{page}` in whichever slot you want the
number aligned to, or let `numbering` place it for you.

#### Logos in the header or footer

Any slot can carry an image next to (or instead of) its text:

```elixir
header: %{
  left: %{image: %{src: "https://cdn.example.com/logo.png", height: 12}},
  center: "",
  right: "{date}"
}
```

`:height` is millimetres; the width follows the aspect ratio and the image is
clamped to the margin it sits in. In the editor the page dialog gives every
slot a logo field with an **upload button** that posts to the same
`upload_url` as the rest of the editor and fills in the returned URL — so
logos go through your existing `Tiptapex.Upload` handler, validation
included. Without `upload_url` the field still accepts a pasted URL.

`src` must be http(s), a relative path, or a `data:` URI for an image;
anything else is dropped, the same allow-list the document renderer applies.

#### Formatting the text

Slot text accepts a small HTML subset — `<b>`, `<i>`, `<u>`, `<s>`, `<span
style="…">`, `<h1>`…`<h6>`, `<p>`, `<div>`, `<a>`, `<img>`, `<br>` and a few
more:

```elixir
footer: %{center: ~s(<span style="color: #6b7280">Page <b>{page}</b> of {pages}</span>)}
```

It is **not** raw HTML: `Tiptapex.Renderer.Markup` tokenises the string,
checks every tag and attribute against a closed allow-list, and rebuilds the
output — so nothing from the field is ever emitted verbatim. `style`
declarations go through the same CSS grammar as document styles, `href` and
`src` through the same URL allow-lists, and anything unrecognised (a
`<script>`, an `onclick`, a malformed tag) comes out as visible text rather
than markup. The editor renders the identical subset client-side with
`createElement`, never `innerHTML`.

wkhtmltopdf's `--header-left` flags render literally, so a slot with markup
takes the same `--header-html` route as a logo — `with_pdf_generator/3`
handles it.

The setup lives **in the document** (`doc.attrs.page`), so it travels with the
JSON you already persist and the exporter needs nothing else. The toolbar's
page button opens a setup dialog whose first control — *Paginate this
document* — is what turns page layout on and off; `page={...}` on the
component overrides whatever the document carries, and `page={false}` forces
the classic continuous editor.

Users insert a forced break with the toolbar or `Cmd/Ctrl+Shift+Enter`.

> #### Collaborative editors: pass `page` explicitly {: .warning}
>
> Yjs syncs the document's *content*, not the `doc` node's attributes — so a
> page setup changed by one peer does not reach the others. Pass `page={...}`
> from the server (and push changes with `Tiptapex.Components.set_page/3`) so
> everyone renders the same paper.

#### Exporting

`Tiptapex.Export.PDF` builds the print-ready HTML and the exact options each
engine needs. It shells out to nothing and adds no dependency — you call the
engine.

```elixir
# ChromicPDF
{source, opts} = Tiptapex.Export.PDF.chromic_pdf(article.body)
ChromicPDF.print_to_pdf(source, opts ++ [output: "article.pdf"])

# pdf_generator (wkhtmltopdf)
{html, opts} = Tiptapex.Export.PDF.pdf_generator(article.body)
{:ok, path} = PdfGenerator.generate(html, opts)

# anything else — browser print, WeasyPrint, Gotenberg…
html = Tiptapex.Export.PDF.to_html(article.body)
```

Both engines draw the running header/footer themselves — the only way to get
a correct `{pages}` total — and the three slots map straight onto their native
features:

| Token | ChromicPDF (Chrome) | pdf_generator (wkhtmltopdf) |
| --- | --- | --- |
| `{page}` | `<span class="pageNumber">` | `[page]` |
| `{pages}` | `<span class="totalPages">` | `[topage]` |
| `{date}` | `<span class="date">` | `[date]` |
| `{title}` | `<span class="title">` | `[title]` |

Pass `tokens: %{"date" => "24/07/2026"}` to substitute one yourself.

Two things to know about logos when exporting:

- **Chrome resolves no relative URLs** in a running header, so give the logo
  an absolute URL or pass `asset_url: &absolutise/1` to rewrite it (inlining
  it as a `data:` URI works well).
- **wkhtmltopdf cannot put an image in `--header-left`.** A region with a logo
  needs `--header-html`, so use `with_pdf_generator/3`, which writes those
  files and cleans them up:

  ```elixir
  Tiptapex.Export.PDF.with_pdf_generator(doc, [], &PdfGenerator.generate/2)
  ```

  Plain `pdf_generator/2` still works — it exports the text and logs that it
  dropped the logo.

The exported HTML inlines this package's stylesheet and repeats the paged
editor's margin model, so what you see in the editor is what the engine
paginates. A read-only preview works too:

```heex
<.tiptapex_viewer id="preview" value={@doc} />
```

### Uploads

Implement the behaviour with your storage:

```elixir
defmodule MyApp.EditorUploads do
  @behaviour Tiptapex.Upload

  @impl true
  def store(%Plug.Upload{} = upload, %{scope: article_id}) do
    # S3, local disk, your Attachments context…
    {:ok, %{url: url, content_type: type, filename: name}}
  end
end
```

Mount the controller in an authenticated pipeline:

```elixir
defmodule MyAppWeb.EditorUploadController do
  use MyAppWeb, :controller
  use Tiptapex.Upload.Controller, handler: MyApp.EditorUploads
end

# router.ex
post "/admin/tiptapex/uploads", EditorUploadController, :create
```

Size limits and **magic-byte content-type verification** run before your handler is called. `Tiptapex.Upload.LocalDisk` is included for demos/simple apps.

### Realtime collaboration

Server — mount a channel:

```elixir
# user_socket.ex
channel "doc:*", MyAppWeb.DocChannel

defmodule MyAppWeb.DocChannel do
  use Tiptapex.Collab.Channel

  @impl true
  def authorize("doc:" <> slug, _params, socket) do
    case MyApp.Docs.get_by_slug(slug) do
      nil -> {:error, %{reason: "not_found"}}
      _doc -> {:ok, socket}
    end
  end
end
```

Client — build the hook with the collab plugin (separate import so yjs stays out of non-collab bundles):

```js
import { makeEditorHook, TiptapexViewerHook } from "tiptapex"
import { CollabPlugin } from "tiptapex/collaboration"

const hooks = {
  TiptapexEditor: makeEditorHook({ collab: CollabPlugin }),
  TiptapexViewer: TiptapexViewerHook,
}
```

Component:

```heex
<.tiptapex_editor
  id="body"
  value={@doc}
  collab={%{
    topic: "doc:" <> @slug,
    socket_path: "/socket",
    user: Tiptapex.Collab.user(%{id: @current_user.id, name: @current_user.name})
  }}
/>
```

The server relays binary Yjs sync/awareness messages between peers; your save flow remains the source of truth. Optional `load_state/2` / `persist_update/3` callbacks support snapshotting — see `Tiptapex.Collab.Channel`.

### HTML source view with CodeMirror

The toolbar's `</>` button swaps the WYSIWYG surface for an editable HTML source view. Out of the box it is a plain `<textarea>`; upgrade it to a full code editor (syntax highlighting, line numbers, autocompletion for HTML/CSS) by installing the optional CodeMirror peers and building your hook with it:

```sh
npm install codemirror @codemirror/lang-html @codemirror/view @codemirror/commands
```

```js
import { makeEditorHook } from "tiptapex"
import { CodeMirrorHtmlEditor } from "tiptapex/html-editor"

const TiptapexEditor = makeEditorHook({ htmlEditor: CodeMirrorHtmlEditor })
```

Like collaboration, this is a separate entry point so CodeMirror stays out of bundles that don't use it. Any object implementing the same surface contract (`create/getValue/setValue/focus/destroy`) can be passed instead — see `assets/js/tiptapex/html-view.js`.

### Custom Tiptap extensions

```js
import { makeEditorHook } from "tiptapex"
import { MyCallout } from "./extensions/callout"

const TiptapexEditor = makeEditorHook({
  extend: (extensions) => [...extensions, MyCallout],
  toolbar: { custom: [{ icon: () => myIcon(), title: "Callout", run: (e) => e.commands.toggleCallout() }] },
})
```

Teach the server renderer about the node:

```elixir
Tiptapex.Renderer.to_html(doc, nodes: %{"callout" => MyApp.CalloutRenderer})
```

## Upload wire contract

The hook POSTs `multipart/form-data` with a `file` part (plus `scope` when configured) and the `x-csrf-token` header. The endpoint must reply:

```json
{ "url": "/uploads/abc.png", "content_type": "image/png", "filename": "abc.png" }
```

`image/*` inserts an image, `video/*` a video node, anything else a download link. `Tiptapex.Upload.Controller` implements this contract for you.

## Working on tiptapex itself

```bash
mix deps.get
mix test

# demo app
cd dev/assets && npm install && cd ../..
mix dev.assets            # bundle the demo JS
mix js.test               # pure-logic JS checks (page maths, pagination)
iex -S mix dev            # http://localhost:4400 (two tabs → collaboration)
```

The demo exports real PDFs through both engines, which is how the option
builders above get exercised end to end:

| Route | What it does |
| --- | --- |
| `/print` | the print-ready HTML `Tiptapex.Export.PDF.to_html/2` builds |
| `/print/chromic` | a PDF via `ChromicPDF` — needs Chrome/Chromium installed |
| `/print/wkhtmltopdf` | a PDF via `pdf_generator` — needs `wkhtmltopdf` on PATH |

Both engines are `only: :dev` dependencies of this repo, never of the
package. The demo boots without either; the route reports what is missing.

## License

MIT — see [LICENSE](LICENSE).
