// Floating contextual menu for the Tiptap `@tiptap/extension-table` node.
//
// What it does:
//
// - Shows a horizontal toolbar floating above the `<table>` whenever the
//   ProseMirror selection is inside any table cell.
// - Exposes the essential structural commands as one-click buttons: add /
//   delete row, add / delete column, toggle header row, merge / split
//   cells, and delete table.
// - Hides itself the moment the selection leaves the table so it never
//   obscures the rest of the doc.
//
// We deliberately don't use `@tiptap/extension-bubble-menu` here because we
// want anchoring to the table itself (not the caret) so the menu stays in
// place even when the user moves between cells. Positioning is done by
// reading the table's bounding rect on every `selectionUpdate`.

import { Editor } from "@tiptap/core"

const svgNS = "http://www.w3.org/2000/svg"

export const DEFAULT_TABLE_LABELS = {
  menu: "Table actions",
  rowAbove: "Insert row above",
  rowBelow: "Insert row below",
  rowDelete: "Delete row",
  colLeft: "Insert column left",
  colRight: "Insert column right",
  colDelete: "Delete column",
  headerToggle: "Toggle header row",
  merge: "Merge cells",
  split: "Split cell",
  tableDelete: "Delete table",
}

function icon(paths, opts = {}) {
  const s = document.createElementNS(svgNS, "svg")
  s.setAttribute("viewBox", "0 0 20 20")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", opts.weight || "1.6")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.setAttribute("aria-hidden", "true")
  paths.forEach((d) => {
    const p = document.createElementNS(svgNS, "path")
    p.setAttribute("d", d)
    s.appendChild(p)
  })
  return s
}

const ICONS = {
  rowAdd: () => icon(["M3 5h14", "M3 10h14", "M3 15h14", "M10 3v4", "M8 5h4"]),
  rowDel: () => icon(["M3 5h14", "M3 10h14", "M3 15h14", "M7 15l6-6", "M7 9l6 6"]),
  colAdd: () => icon(["M4 4v12", "M10 4v12", "M16 4v12", "M10 2v4", "M8 4h4"]),
  colDel: () => icon(["M4 4v12", "M10 4v12", "M16 4v12", "M7 8l6 4", "M7 12l6-4"]),
  header: () =>
    icon(["M3 5h14v3H3z", "M3 10h14", "M3 14h14", "M7 5v12", "M13 5v12"]),
  merge: () =>
    icon([
      "M3 5h6v4H3z",
      "M11 11h6v4h-6z",
      "M9 7h2v4h2",
    ]),
  split: () => icon(["M3 4v12", "M10 4v12", "M17 4v12", "M5 10h2", "M14 10h2"]),
  trash: () =>
    icon([
      "M4 6h12",
      "M8 6V4h4v2",
      "M5 6l1 10a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2l1-10",
      "M9 9v6",
      "M11 9v6",
    ]),
}

function button({ icon, title, onClick }) {
  const b = document.createElement("button")
  b.type = "button"
  b.className = "ttx-table-menu-btn"
  // `aria-label` powers screen readers; `data-tooltip` powers the
  // custom CSS tooltip rendered just below the button. We skip the
  // browser-native `title` attribute on purpose so we don't get a
  // duplicate tooltip alongside ours.
  b.setAttribute("aria-label", title)
  b.dataset.tooltip = title
  b.appendChild(icon)
  b.addEventListener("mousedown", (e) => {
    // Prevent ProseMirror from losing the selection when clicking the menu.
    e.preventDefault()
  })
  b.addEventListener("click", (e) => {
    e.preventDefault()
    onClick()
  })
  return b
}

function group(buttons) {
  const g = document.createElement("div")
  g.className = "ttx-table-menu-group"
  buttons.forEach((b) => g.appendChild(b))
  return g
}

/**
 * Attaches the floating table menu to the editor. Returns a detach function
 * that the hook calls on destroy().
 */
export function attachTableMenu(editor, host, labels = {}) {
  if (!(editor instanceof Editor)) return () => {}

  const t = { ...DEFAULT_TABLE_LABELS, ...labels }

  const menu = document.createElement("div")
  menu.className = "ttx-table-menu"
  menu.setAttribute("role", "toolbar")
  menu.setAttribute("aria-label", t.menu)
  menu.style.display = "none"

  // Row group
  menu.appendChild(
    group([
      button({
        icon: ICONS.rowAdd(),
        title: t.rowAbove,
        onClick: () => editor.chain().focus().addRowBefore().run(),
      }),
      button({
        icon: ICONS.rowAdd(),
        title: t.rowBelow,
        onClick: () => editor.chain().focus().addRowAfter().run(),
      }),
      button({
        icon: ICONS.rowDel(),
        title: t.rowDelete,
        onClick: () => editor.chain().focus().deleteRow().run(),
      }),
    ])
  )

  // Column group
  menu.appendChild(
    group([
      button({
        icon: ICONS.colAdd(),
        title: t.colLeft,
        onClick: () => editor.chain().focus().addColumnBefore().run(),
      }),
      button({
        icon: ICONS.colAdd(),
        title: t.colRight,
        onClick: () => editor.chain().focus().addColumnAfter().run(),
      }),
      button({
        icon: ICONS.colDel(),
        title: t.colDelete,
        onClick: () => editor.chain().focus().deleteColumn().run(),
      }),
    ])
  )

  // Header / merge / split / delete table
  menu.appendChild(
    group([
      button({
        icon: ICONS.header(),
        title: t.headerToggle,
        onClick: () => editor.chain().focus().toggleHeaderRow().run(),
      }),
      button({
        icon: ICONS.merge(),
        title: t.merge,
        onClick: () => editor.chain().focus().mergeCells().run(),
      }),
      button({
        icon: ICONS.split(),
        title: t.split,
        onClick: () => editor.chain().focus().splitCell().run(),
      }),
      button({
        icon: ICONS.trash(),
        title: t.tableDelete,
        onClick: () => editor.chain().focus().deleteTable().run(),
      }),
    ])
  )

  // Append to body so the menu floats above everything and is never
  // clipped by overflow: hidden on intermediate containers.
  document.body.appendChild(menu)

  // Find the <td>/<th> the cursor is currently inside. We anchor to the
  // active cell rather than the whole table so the menu always hovers
  // right above the row the user is editing — useful for big tables
  // where the table top might be far above the cursor.
  const findActiveCell = () => {
    const { from } = editor.state.selection
    const at = editor.view.domAtPos(from)
    if (!at) return null
    const node = at.node instanceof Element ? at.node : at.node.parentElement
    return node?.closest("td, th") || null
  }

  const update = () => {
    if (!editor.isActive("table")) {
      menu.style.display = "none"
      return
    }
    const cell = findActiveCell()
    if (!cell) {
      menu.style.display = "none"
      return
    }

    // Use viewport coordinates directly with `position: fixed`. Avoids
    // host coord-system gotchas (flex layout shifts, sticky toolbar,
    // window scroll). Reattach the menu to <body> so nothing inside the
    // editor can clip it.
    menu.style.visibility = "hidden"
    menu.style.display = "inline-flex"
    const menuH = menu.offsetHeight
    const menuW = menu.offsetWidth

    const cellRect = cell.getBoundingClientRect()

    let top = cellRect.top - menuH - 6
    let left = cellRect.left

    // If there's no room above (top of viewport), flip below the cell.
    if (top < 8) top = cellRect.bottom + 6

    // Clamp horizontally to the viewport.
    const maxLeft = window.innerWidth - menuW - 8
    if (maxLeft > 8) left = Math.min(Math.max(8, left), maxLeft)

    menu.style.top = `${top}px`
    menu.style.left = `${left}px`
    menu.style.visibility = "visible"
  }

  const onSelect = () => update()
  const onTx = () => update()
  editor.on("selectionUpdate", onSelect)
  editor.on("transaction", onTx)
  // Reposition on resize and any scroll (capture phase catches scroll on
  // every nested scroller in the host layout).
  window.addEventListener("resize", update, { passive: true })
  window.addEventListener("scroll", update, { passive: true, capture: true })

  return function detach() {
    editor.off("selectionUpdate", onSelect)
    editor.off("transaction", onTx)
    window.removeEventListener("resize", update)
    window.removeEventListener("scroll", update, { capture: true })
    menu.remove()
  }
}
