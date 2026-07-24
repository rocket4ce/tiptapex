# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rocket4ce/tiptapex/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/rocket4ce/tiptapex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rocket4ce/tiptapex/releases/tag/v0.1.0
