// Exercises the pagination maths against the same page geometry the browser
// would compute. Blocks are fed in as measured heights, which is exactly what
// PaginationView.collectBlocks() produces from the DOM.
import assert from "node:assert/strict"

import { test } from "./harness.mjs"
import { computeBreaks } from "tiptapex/pagination"
import { normalizePage, pageGeometry } from "tiptapex/page"

const geom = pageGeometry(normalizePage({ size: "letter" })) // contentHeight = 864px
const H = geom.contentHeight

const block = (height, { gap = 0, isBreak = false, pos = 0 } = {}) => ({ pos, height, gap, isBreak })
const blocks = (list) => list.map((b, i) => ({ ...b, pos: i * 10 }))

const t = (name, fn) => test("pagination", name, fn)

t("an empty document is one page with no breaks", () => {
  const r = computeBreaks([], geom)
  assert.deepEqual(r.breaks, [])
  assert.equal(r.pages, 1)
})

t("content that fits stays on one page", () => {
  const r = computeBreaks(blocks([block(400), block(400)]), geom)
  assert.deepEqual(r.breaks, [])
  assert.equal(r.pages, 1)
  assert.equal(r.used, 800)
})

t("the block that overflows starts the next page", () => {
  const r = computeBreaks(blocks([block(500), block(400), block(100)]), geom)
  assert.equal(r.pages, 2)
  assert.equal(r.breaks.length, 1)
  assert.equal(r.breaks[0].pos, 10, "the break sits before the second block")
  assert.equal(r.breaks[0].fill, H - 500, "the gap fills the rest of page 1")
  assert.equal(r.breaks[0].forced, false)
  assert.equal(r.used, 500, "page 2 holds the 400 + 100 blocks")
})

t("bottom margins count against the page", () => {
  const r = computeBreaks(blocks([block(800, { gap: 100 }), block(50)]), geom)
  assert.equal(r.pages, 2, "800 + 100 of margin leaves no room for another 50px block")
  assert.equal(r.breaks.length, 1, "and the sheet boundary is actually drawn")
  assert.equal(r.breaks[0].fill, 0)
})

t("a trailing margin that overflows is swallowed, not carried onto the next page", () => {
  const r = computeBreaks(blocks([block(860, { gap: 40 }), block(50)]), geom)
  assert.equal(r.pages, 2)
  assert.equal(r.breaks.length, 1)
  assert.equal(r.breaks[0].fill, 0, "the gap never goes negative")
  assert.equal(r.used, 50, "the 50px block sits at the top of page 2")
})

t("a block taller than the page flows across sheets instead of looping", () => {
  const r = computeBreaks(blocks([block(H * 3 + 100)]), geom)
  assert.equal(r.pages, 4)
  assert.deepEqual(r.breaks, [], "an oversized block gets no gap — it spans the sheets")
})

t("an oversized first block still leaves the remainder on the last page", () => {
  const r = computeBreaks(blocks([block(H * 2 + 200)]), geom)
  assert.equal(r.pages, 3)
  assert.equal(Math.round(r.used), 200)
})

t("a forced break closes the page wherever it sits", () => {
  const r = computeBreaks(blocks([block(100), block(0, { isBreak: true }), block(100)]), geom)
  assert.equal(r.pages, 2)
  assert.equal(r.breaks.length, 1)
  assert.equal(r.breaks[0].forced, true)
  assert.equal(r.breaks[0].pos, 10, "the gap renders at the break node's own position")
  assert.equal(r.breaks[0].fill, H - 100)
})

t("a leading break collapses rather than making a blank first page", () => {
  const r = computeBreaks(blocks([block(0, { isBreak: true }), block(100)]), geom)
  assert.deepEqual(r.breaks, [])
  assert.equal(r.pages, 1)
})

t("consecutive breaks collapse, like break-after: page does", () => {
  const r = computeBreaks(
    blocks([block(100), block(0, { isBreak: true }), block(0, { isBreak: true }), block(100)]),
    geom
  )
  assert.equal(r.breaks.length, 1)
  assert.equal(r.pages, 2)
})

t("a trailing break yields one more, empty page", () => {
  const r = computeBreaks(blocks([block(100), block(0, { isBreak: true })]), geom)
  assert.equal(r.pages, 2)
  assert.equal(r.used, 0, "the tail fills the whole empty page")
})

t("forced and automatic breaks interleave correctly", () => {
  const r = computeBreaks(
    blocks([block(100), block(0, { isBreak: true }), block(800), block(200)]),
    geom
  )
  assert.equal(r.pages, 3)
  assert.deepEqual(
    r.breaks.map((b) => b.forced),
    [true, false]
  )
})

t("many small blocks paginate evenly", () => {
  const r = computeBreaks(blocks(Array.from({ length: 100 }, () => block(100))), geom)
  // 8 blocks (800px) per 864px page, 100 blocks -> 13 pages.
  assert.equal(r.pages, 13)
  assert.equal(r.breaks.length, 12)
})
