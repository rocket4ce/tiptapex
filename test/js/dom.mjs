// One jsdom for the whole run. Two files each building their own would leave
// the globals pointing at one document while elements were created in the
// other — silently breaking anything that measures or queries.
import { JSDOM } from "jsdom"

export const dom = new JSDOM("<!doctype html><html><body></body></html>", { pretendToBeVisual: true })

const GLOBALS = [
  "window",
  "document",
  "navigator",
  "Node",
  "Element",
  "HTMLElement",
  "DOMParser",
  "MutationObserver",
  "getComputedStyle",
  "requestAnimationFrame",
  "cancelAnimationFrame",
]

for (const key of GLOBALS) {
  if (globalThis[key] === undefined) globalThis[key] = dom.window[key]
}

// jsdom ships no ResizeObserver; the pagination plugin treats it as optional.
if (globalThis.ResizeObserver === undefined) globalThis.ResizeObserver = undefined

// jsdom has no layout: every element measures 0×0, so the paginator would
// never decide a page is full and the gap-widget path would go unexercised.
// Give top-level editor blocks a height so real breaks get built and rendered.
export const BLOCK_HEIGHT = 300

dom.window.Element.prototype.getBoundingClientRect = function () {
  const height = this.parentElement?.classList.contains("ProseMirror") ? BLOCK_HEIGHT : 0
  return { x: 0, y: 0, top: 0, left: 0, right: 0, bottom: height, width: 0, height, toJSON: () => ({}) }
}
