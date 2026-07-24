# Tiptapex

**[Tiptap](https://tiptap.dev) v3 rich-text editing for Phoenix LiveView (Phoenix ≥ 1.8, LiveView ≥ 1.1).**

Tiptapex packages a production-grade editor integration as a single Hex package:

- **`<.tiptapex_editor>` / `<.tiptapex_viewer>`** — HEEx function components backed by JS hooks shipped inside this package.
- **A full-featured editor** — toolbar (marks, headings, alignment, lists, fonts, colors), resizable images and videos (file + YouTube embeds), tables with a floating context menu, task lists, drag-handle block reordering, placeholder, character count, invisible characters, editable HTML source view.
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
    {:tiptapex, "~> 0.1.1"}
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
| `toolbar={[:marks, :blocks, :lists, :history]}` | ordered subset of groups; `false` hides the toolbar |
| `extensions={%{table: false, character_count_limit: 10_000}}` | per-feature switches for the JS extension matrix |
| `extensions={%{html_view: false}}` | disables the toolbar's editable HTML source view (`</>` button) |
| `labels={%{bold: "Negrita", insert_link: "Insertar enlace"}}` | i18n for toolbar/table menu (English defaults) |
| `remount_key={@editor_session}` | bump to force a client remount (e.g. after restoring a version) |
| `count_template="{chars} caracteres · {words} palabras"` | footer counter format |
| `<:actions>` slot | render buttons in the editor footer |

Push content into a mounted editor from the server (multiple editors are namespaced by id):

```elixir
{:noreply, Tiptapex.Components.set_content(socket, "article-body", restored.body)}
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
iex -S mix dev            # http://localhost:4400 (two tabs → collaboration)
```

## License

MIT — see [LICENSE](LICENSE).
