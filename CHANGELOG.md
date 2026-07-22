# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rocket4ce/tiptapex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rocket4ce/tiptapex/releases/tag/v0.1.0
