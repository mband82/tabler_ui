// Builds the Structure tab's markup: a flat, indented outline of the
// current file's design tree, one row per node plus one pseudo-row per
// named slot on a slot-style component (so a slot can be selected as an
// insertion target even before it holds any content). Each node row
// carries move-up / move-down / delete buttons -- the non-drag-and-drop
// way to reorder and remove nodes. SortableJS is a later, purely additive
// enhancement (a separate agent's work); a host with a strict CSP will
// never load it, so these buttons are the real mechanism, not a fallback
// for one that doesn't otherwise exist.
//
// Pure functions only -- the controller owns all DOM writes and event
// wiring, and is responsible for calling this only on a genuine structural
// change (add/move/delete/select), never on every keystroke of an option
// edit -- see editor_controller.js's own header for why (rebuilding an
// element mid-edit steals focus/caret, the same lesson
// search_controller.js's own header documents).
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"

export function labelFor(node) {
  switch (node.kind) {
    case "fragment": return "(root)"
    case "row": return "Row"
    case "column": return "Column"
    case "heading": return `Heading: ${truncate(node.content)}`
    case "text": return `Text: ${truncate(node.content)}`
    case "partial": return `Partial: ${node.path || "(none)"}`
    case "component": return `Component: ${node.name}`
    case "builder_item": return node.method || "(item)"
    default: return node.kind
  }
}

function truncate(text) {
  const value = (text || "").trim()
  if (value === "") return "(empty)"
  return value.length > 40 ? `${value.slice(0, 40)}...` : value
}

function childArrays(node) {
  const arrays = []
  if (Array.isArray(node.children)) arrays.push(node.children)
  if (Array.isArray(node.items)) arrays.push(node.items)
  return arrays
}

function isSelectedSlot(selectedSlot, nodeId, slotName) {
  return !!selectedSlot && selectedSlot.nodeId === nodeId && selectedSlot.slotName === slotName
}

function rowHtml(node, depth, selectedId) {
  const active = node.id === selectedId ? " active" : ""
  const indent = (depth * 0.9).toFixed(2)

  return `
    <div class="list-group-item list-group-item-action py-1 d-flex align-items-center justify-content-between docs-editor-structure-row${active}"
         style="padding-left: ${indent}rem"
         data-action="click->tabler-ui--docs-editor#selectStructureNode"
         data-editor-node-id="${node.id}" role="button">
      <span class="text-truncate small docs-editor-structure-label">${escapeHtml(labelFor(node))}</span>
      <span class="btn-list ms-2">
        <button type="button" class="btn btn-sm btn-icon btn-ghost-secondary" title="Move up"
                data-action="click->tabler-ui--docs-editor#moveNodeUp" data-editor-node-id="${node.id}">&uarr;</button>
        <button type="button" class="btn btn-sm btn-icon btn-ghost-secondary" title="Move down"
                data-action="click->tabler-ui--docs-editor#moveNodeDown" data-editor-node-id="${node.id}">&darr;</button>
        <button type="button" class="btn btn-sm btn-icon btn-ghost-danger" title="Delete"
                data-action="click->tabler-ui--docs-editor#deleteNode" data-editor-node-id="${node.id}">&times;</button>
      </span>
    </div>
  `
}

function slotRowHtml(nodeId, slotName, depth, selectedSlot) {
  const active = isSelectedSlot(selectedSlot, nodeId, slotName) ? " active" : ""
  const indent = (depth * 0.9).toFixed(2)

  return `
    <div class="list-group-item list-group-item-action py-1 docs-editor-structure-row docs-editor-structure-slot${active}"
         style="padding-left: ${indent}rem"
         data-action="click->tabler-ui--docs-editor#selectSlot"
         data-editor-node-id="${nodeId}" data-editor-slot="${escapeHtml(slotName)}" role="button">
      <span class="text-secondary small">slot: ${escapeHtml(slotName)}</span>
    </div>
  `
}

function walk(schema, node, depth, selectedId, selectedSlot) {
  let html = node.kind === "fragment" ? "" : rowHtml(node, depth, selectedId)
  const nextDepth = node.kind === "fragment" ? depth : depth + 1

  if (node.kind === "component" && node.slots) {
    const meta = schema && schema.components && schema.components[node.name]
    const slotNames = (meta && meta.slots) || Object.keys(node.slots)
    slotNames.forEach((slotName) => {
      html += slotRowHtml(node.id, slotName, nextDepth, selectedSlot)
      const children = node.slots[slotName] || []
      children.forEach((child) => { html += walk(schema, child, nextDepth + 1, selectedId, selectedSlot) })
    })
  }

  childArrays(node).forEach((arr) => {
    arr.forEach((child) => { html += walk(schema, child, nextDepth, selectedId, selectedSlot) })
  })

  return html
}

// @param schema [Object, null] the /ui/editor/schema payload, used only to
//   look up a slot-style component's real slot names (schema.components[name].slots)
//   -- falls back to whatever slot keys the node already has if schema
//   hasn't loaded yet.
// @param tree [Object, null] the current file's design tree.
// @param selectedId [String, null]
// @param selectedSlot [{nodeId, slotName}, null]
export function structureHtml(schema, tree, selectedId, selectedSlot) {
  if (!tree) return '<p class="text-secondary small mb-0">No file open.</p>'

  const html = walk(schema, tree, 0, selectedId, selectedSlot)
  return html || '<p class="text-secondary small mb-0">Empty -- add something from the Components tab.</p>'
}
