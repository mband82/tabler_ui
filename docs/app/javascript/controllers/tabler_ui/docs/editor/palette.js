// Builds the Components tab's markup from the /ui/editor/schema payload
// (see docs/lib/tabler_ui/docs/editor/schema.rb's module doc for the
// "layout"/"categories"/"components" shape). Pure functions only -- the
// controller owns all DOM writes and event wiring (rule 6, CLAUDE.md).
//
// Every item carries data-editor-kind (and, for a component, data-editor-
// component) so editor_controller.js#addFromPalette can build the right
// node kind without this module needing to know anything about the tree.
//
// Each item is also draggable="true" and carries dragstart/dragend actions
// (editor_controller.js#paletteDragStart/#paletteDragEnd) alongside the
// click action -- dragging onto the canvas is additive on top of
// click-to-insert, never a replacement for it. This markup duplicates
// docs/app/views/tabler_ui/docs/editor/show.html.erb's own no-JS fallback
// palette item -- see that view's comment for why the two must stay in
// sync by hand.
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"

const LAYOUT_LABELS = {
  row: "Row",
  column: "Column",
  heading: "Heading",
  text: "Text",
  partial: "Partial"
}

export function paletteHtml(schema) {
  const layout = layoutSectionHtml(schema)
  const categories = (schema.categories || []).map((category) => categoryHtml(schema, category)).join("")
  return `${layout}${categories}`
}

function paletteItemHtml(label, dataAttrs) {
  return `
    <div class="list-group-item list-group-item-action py-1 docs-editor-palette-item"
         draggable="true"
         data-action="click->tabler-ui--docs-editor#addFromPalette dragstart->tabler-ui--docs-editor#paletteDragStart dragend->tabler-ui--docs-editor#paletteDragEnd"
         ${dataAttrs}>
      ${escapeHtml(label)}
    </div>
  `
}

function layoutSectionHtml(schema) {
  const items = (schema.layout || []).map((entry) => {
    const label = LAYOUT_LABELS[entry.kind] || entry.kind
    return paletteItemHtml(label, `data-editor-kind="${escapeHtml(entry.kind)}"`)
  }).join("")

  // Deliberately not "Layout": Navigation's own component categories include
  // one called Layout (accordion, card, table, ...), and rendering both under
  // the same heading put two identical "Layout" headings in one scrolling
  // list with unrelated contents under each.
  return `<h4 class="mt-2">Structure &amp; text</h4><div class="list-group list-group-flush mb-2">${items}</div>`
}

function categoryHtml(schema, category) {
  const items = (category.components || []).map((name) => {
    const component = schema.components && schema.components[name]
    const title = component ? component.title : name
    return paletteItemHtml(title, `data-editor-kind="component" data-editor-component="${escapeHtml(name)}"`)
  }).join("")

  return `
    <h4 class="mt-2">${escapeHtml(category.label)}</h4>
    <div class="list-group list-group-flush mb-2">${items}</div>
  `
}
