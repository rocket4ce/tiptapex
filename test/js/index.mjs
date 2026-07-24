// Entry point for `mix js.test` — bundled by esbuild (so the `@tiptap/*`
// peers resolve exactly as they do in a host app) and run with node.
import "./page_test.mjs"
import "./markup_test.mjs"
import "./pagination_test.mjs"
import "./editor_test.mjs"

import { report } from "./harness.mjs"

await report()
