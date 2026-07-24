# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-07-24

### Added

- **Page layout.** Documents can now carry a page setup — paper size
  (`:letter`, `:legal`, `:a4`, `:a5`, `:tabloid`, `:executive` or a custom
  `%{width:, height:}`), orientation, margins, running headers and footers,
  and page numbering — on the `doc` node's `attrs.page`. `Tiptapex.Page`
  reads, merges, validates and stores it; lengths are millimetres and accept
  CSS units (`"1in"`, `"2cm"`, `"72pt"`, `"96px"`).
- **Live pagination in the editor.** When a document has a page setup, the
  editor renders a stack of measured sheets instead of a continuous surface,
  with the running header and footer drawn in every page's margins. Nothing
  is written to the document — the breaks are ProseMirror decorations, so
  undo/redo, collaboration and the persisted JSON are untouched. New JS
  exports: `Pagination`, `computeBreaks`, `paginationKey`.
- **Headers and footers** with three slots each (`left`, `center`, `right`)
  and the tokens `{page}`, `{pages}`, `{date}`, `{time}`, `{title}`. Page
  numbering (`numbering: %{enabled:, region:, align:, format:}`) drops the
  number into the slot you name, so left/centre/right numbering is a
  one-liner.
- **Logos in headers and footers.** A slot is either a string (text) or
  `%{text: ..., image: %{src:, height:, alt:}}`, with `:height` in
  millimetres. The page dialog gives every slot a logo field with an upload
  button that posts to the editor's own `upload_url`, so logos run through
  the host's `Tiptapex.Upload` handler and its validation. `src` is held to
  the same allow-list as document URLs, plus `data:` URIs for images — which
  is what Chrome needs, since it resolves no relative URLs in a running
  header. New: `Tiptapex.Page.images?/1`, `Tiptapex.Export.PDF.running_html/3`
  and `Tiptapex.Export.PDF.with_pdf_generator/3` (wkhtmltopdf cannot draw an
  image from `--header-left`, so a region with a logo needs `--header-html`;
  this writes those files and cleans them up). The JS upload contract is now
  also exposed on its own as `uploadFile/2`.
- **Formatting in header/footer text.** Slots accept a small allow-listed
  HTML subset (`<b>`, `<span style="…">`, `<h1>`, `<a>`, `<img>`, …) via the
  new `Tiptapex.Renderer.Markup`, which tokenises the string, validates every
  tag and attribute against a closed list and rebuilds the output — nothing
  from the field is emitted verbatim, so an unknown tag or an `onclick`
  becomes visible text rather than markup. `style` reuses the document CSS
  grammar and URLs the document allow-lists; the editor renders the same
  subset with `createElement`, never `innerHTML`. New:
  `Tiptapex.Renderer.URL.safe_image_url/1` (shared by logos and markup) and
  the JS `renderMarkup`/`hasMarkup`/`safeUrl`/`safeImageUrl`/`safeCssValue`
  exports.
- **Forced page breaks** — a new `pageBreak` node, the toolbar's page-break
  button, `Cmd/Ctrl+Shift+Enter`, and `editor.commands.setPageBreak()`. The
  server renderer emits `<div data-page-break>` with the CSS break inline.
- **`Tiptapex.Export.PDF`** — print-ready HTML plus ready-made options for
  the two common engines, with no new dependency: `chromic_pdf/2` returns
  `{source, opts}` for `ChromicPDF.print_to_pdf/2`, `pdf_generator/2` returns
  `{html, opts}` for `PdfGenerator.generate/2`, and `to_html/2` covers
  everything else. Header/footer slots are translated to each engine's native
  running elements (`<span class="pageNumber">` / `[page]`), so `{pages}` and
  per-page numbering are always correct. The exported HTML inlines the
  package stylesheet and mirrors the paged editor's margin model, so editor
  and PDF break in the same places.
- **New toolbar group `page`** (in the default set): a page-setup dialog
  covering whether the document is paginated at all, size, orientation,
  margins, header/footer slots and logos, numbering and the document title,
  plus the page-break button. Page layout is turned on and off by the
  dialog's first checkbox — *Paginate this document* — so the control is
  always visible and the state is always reversible. The dialog's strings go
  through the existing `labels` map.
- **`page` attribute** on `tiptapex_editor/1` and `tiptapex_viewer/1` —
  `nil` uses the document's own setup, `false` forces a continuous editor,
  and a map/`true` overrides the document. The viewer paginates a document
  with a page setup when hydrated, and gives the server-rendered fallback the
  paper's width and margins.
- **`Tiptapex.Components.set_page/3`** — push a page setup into a mounted
  editor without touching its content. This is also how you keep
  collaborators in step: Yjs syncs the document's content, not the `doc`
  node's attributes.
- `{pages}` is now available in `count_template`.
- `mix js.test` — pure-logic JS checks (page normalisation, which must agree
  with `Tiptapex.Page`, and the pagination maths), wired into CI.

### Fixed

- **The exported PDF now has the margins it was told to have.** Chrome lets a
  CSS `@page { margin }` override the `printToPDF` margin parameters rather
  than adding to them, so emitting `margin: 0` on the ChromicPDF path printed
  the body edge to edge while the running header still sat inside the margin
  box. Both now carry the same values.
- **The print stylesheet now outranks the packaged one.** `.ttx-prose > *`
  loses to `.ttx-prose h1` on specificity, so heading top margins survived
  into the PDF and it paginated out of step with the editor. The print rules
  are scoped under `.ttx-print` and mirror the paged editor's heading
  padding.
- **wkhtmltopdf output is no longer ~25% too small.** It lays out at 75 DPI
  and smart-shrinks the result; `pdf_generator/2` now passes
  `--dpi 96 --disable-smart-shrinking`, which brings its page count in line
  with Chrome's and with the editor.
- **The wkhtmltopdf running header is no longer indented twice.** It already
  lays the header HTML out inside the page margins, so `running_html/3`
  repeating them as padding pushed the logo and date inwards.
- Exported HTML sets a sans-serif stack. Neither `.ttx-prose` nor
  `.ttx-content` declares a font family — in an app the host stylesheet
  supplies one, but a standalone PDF has no host and fell back to the
  engine's default serif.
- The editable HTML source view no longer drops document-level attributes.
  The source carries the content only, so the `doc` node's attributes (the
  page setup) are now carried across explicitly instead of being lost on the
  round trip.

## [0.1.1] - 2026-07-24

### Added

- Editable HTML source view in the editor: a new `html` toolbar group
  (enabled by default, `</>` button) toggles between the WYSIWYG surface
  and a textarea showing the document's pretty-printed HTML. Edits are
  parsed back into the Tiptap document (debounced), so change events and
  hidden-input sync keep working while in source mode. In collaborative
  editors the parsed document is written through the shared Y.Doc so
  source edits propagate to peers. Disable with
  `extensions={%{html_view: false}}`. JS exports: `attachHtmlView/3`,
  `formatHtml/1`, `htmlToJSON/2`.
- Optional CodeMirror 6 surface for the HTML source view: build the hook
  with `makeEditorHook({ htmlEditor: CodeMirrorHtmlEditor })` (new
  `tiptapex/html-editor` entry point, optional `codemirror`/`@codemirror/*`
  peers) to upgrade the source textarea to a real code editor with HTML/CSS
  syntax highlighting, line numbers, and autocompletion. Any object
  implementing the same surface contract can be plugged in instead.

## [0.1.0] - 2026-07-22

### Added

- `Tiptapex.Components.tiptapex_editor/1` and `tiptapex_viewer/1` HEEx
  components with `data-ttx-*`-driven configuration, two sync modes
  (`:push_event` and `{:hidden_input, field}`), per-id namespaced
  `set-content` events, and an `:actions` footer slot.
- JS hooks (`TiptapexEditor`, `TiptapexViewer`) shipped as raw ESM inside
  the Hex package with `@tiptap/*` as npm peer dependencies; configurable
  toolbar (group registry, i18n labels, custom buttons), floating table
  menu, resizable image/video extensions, font-size/line-height/
  background-color/trailing-node/selection-preserve extensions, attachment
  drag & drop.
- `Tiptapex.Renderer` — server-side Tiptap JSON → safe HTML with full
  node/mark coverage, URL and CSS sanitization, YouTube-only iframes,
  extensible node/mark registries, `to_plain_text/1` and `headings/1`.
- `Tiptapex.Upload` behaviour, `Tiptapex.Upload.Controller` macro, and
  `Tiptapex.Upload.Validator` with size limits and magic-byte
  content-type verification; `Tiptapex.Upload.LocalDisk` convenience
  handler.
- `Tiptapex.Collab.Channel` macro implementing the Yjs-over-Phoenix-
  Channels relay protocol, with `authorize/3` and optional
  `load_state/2` / `persist_update/3` hooks; `CollabPlugin` JS entry point
  (`tiptapex/collaboration`) kept separate so yjs stays out of non-collab
  bundles.
- `Tiptapex.Schema.Document` Ecto type (optional `ecto` dependency).
- Themeable stylesheet (`priv/static/tiptapex.css`) scoped under
  `ttx-*` classes with `--ttx-*` custom properties falling back to
  daisyUI tokens.
- Single-file dev/demo server (`iex -S mix dev`).

[Unreleased]: https://github.com/rocket4ce/tiptapex/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/rocket4ce/tiptapex/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/rocket4ce/tiptapex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rocket4ce/tiptapex/releases/tag/v0.1.0
