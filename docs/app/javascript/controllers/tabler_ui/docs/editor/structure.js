// Builds the Structure tab's markup: a nested outline of the current
// file's design tree, one row per node plus one pseudo-row per named slot
// on a slot-style component (so a slot can be selected as an insertion
// target even before it holds any content). Each node row carries
// move-up / move-down / delete buttons -- the non-drag-and-drop way to
// reorder and remove nodes, and the one that keeps working even where
// SortableJS can't load (a strict CSP, offline dev): see
// editor_sortable_controller.js's own header. Drag-and-drop is a purely
// additive enhancement layered on top of these same node wrappers.
//
// ## Real per-array containers, not a flat indented list
//
// SortableJS needs one real DOM container element per array being
// reordered. So, unlike the old flat sibling-`<div>`-per-row markup this
// module used to emit, a node's own sub-containers (its children/slots/
// items arrays) are now rendered INSIDE that node's own wrapper, as
// descendants of it -- a real recursive tree of
// `<div data-editor-container-id="...">` container elements, each holding
// some number of node wrappers, each of which may itself hold further
// containers. Each node wrapper -- not the row inside it -- carries
// `data-editor-item-id`, which is what makes it a direct child of its
// container (SortableJS's `draggable` selector only matches direct
// children) and what makes a drag move the node's whole subtree, not just
// its row. The visual look (row classes, selected-row highlighting,
// indentation via inline padding-left) is unchanged; only the DOM
// structure producing it is.
//
// ## Container id encoding
//
// `structure:<nodeId>:<key>` where `<nodeId>` is the id of the node that
// OWNS the array (the tree's root fragment's own id is "root" --
// editor/workspace.js's emptyWorkspace -- so this covers the top-level
// children array too, no separate "root" literal needed) and `<key>` is
// one of:
//   - "children" -- a fragment/row/column's own children array
//   - "items"    -- a builder-style component's (or a builder_item's own
//                    nested) items array
//   - "slot__<slotName>" -- a slot-style component's named slot (double
//     underscore, not a colon, so a slot name -- which per Contract::
//     NODE_ID's charset never contains ":" or "__" itself -- can't be
//     misread as another field of the encoding)
// editor_controller.js#handleSortableMove is the consumer; it owns this
// encoding jointly with this file.
//
// Pure functions only -- the controller owns all DOM writes and event
// wiring, and is responsible for calling this only on a genuine structural
// change (add/move/delete/select), never on every keystroke of an option
// edit -- see editor_controller.js's own header for why (rebuilding an
// element mid-edit steals focus/caret, the same lesson
// search_controller.js's own header documents).
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"
import { builderMethodDescriptor } from "controllers/tabler_ui/docs/editor/tree"

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

function isSelectedSlot(selectedSlot, nodeId, slotName) {
  return !!selectedSlot && selectedSlot.nodeId === nodeId && selectedSlot.slotName === slotName
}

// The row for one node. `data-editor-node-id` is what every button's/row's
// own `data-action` reads via event delegation. The draggable unit itself
// is not this row but the `.docs-editor-structure-node` wrapper that
// contains it -- see this file's header and renderNode() below -- so that
// dragging a node carries its whole subtree (row plus nested containers)
// as one piece.
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

// The empty-slot pseudo-row -- NOT draggable (no data-editor-item-id), see
// this file's header. Rendered as the sole content of a slot's own
// container when that slot holds nothing yet, so the slot can still be
// selected (click) or dropped into (drag) as an insertion target.
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

// One real, independently-sortable container element wrapping `innerHtml`
// (some number of node wrappers, or -- for an empty slot -- just its
// pseudo-row). `data-action` binds the move event straight to the main
// editor controller; Stimulus wires up dynamically-injected data-actions
// the same way it already does for the buttons above, so no view change is
// needed for this to work.
function containerHtml(containerId, innerHtml) {
  return `
    <div class="docs-editor-structure-container"
         data-controller="tabler-ui--docs-editor-sortable"
         data-action="tabler-ui--docs-editor-sortable:move->tabler-ui--docs-editor#handleSortableMove"
         data-editor-container-id="${containerId}"
         data-tabler-ui--docs-editor-sortable-group-value="structure">${innerHtml}</div>
  `
}

// @param context [{componentName, level}, null] the current builder-map
//   context -- needed to look up a builder_item's own method descriptor
//   (schema.components[name].builder[level][method]) mid-walk. Mirrors
//   editor/tree.js#findNodeContext, which does the same lookup but for one
//   targeted id rather than threaded through a whole-tree walk like this
//   one -- both share the actual lookup (Tree.builderMethodDescriptor) so
//   the two can never disagree about what a method's descriptor says.
function renderArray(schema, nodes, depth, selectedId, selectedSlot, context) {
  return nodes.map((child) => renderNode(schema, child, depth, selectedId, selectedSlot, context)).join("")
}

// The empty-children pseudo-row for a builder item whose own method takes a
// content block (`block: "children"` in the schema payload -- tabs.tab,
// accordion.item, settings_page.item, ...). Same shape/purpose as
// slotRowHtml just above -- a non-draggable placeholder that keeps the
// (currently empty) children container selectable/droppable as an insertion
// target -- but labeled generically ("content") rather than by a slot name,
// since a builder item has exactly one children container, never several
// named ones the way a slot-style component does.
function childrenRowHtml(nodeId, depth, selectedId) {
  const active = nodeId === selectedId ? " active" : ""
  const indent = (depth * 0.9).toFixed(2)

  return `
    <div class="list-group-item list-group-item-action py-1 docs-editor-structure-row docs-editor-structure-slot${active}"
         style="padding-left: ${indent}rem"
         data-action="click->tabler-ui--docs-editor#selectStructureNode"
         data-editor-node-id="${nodeId}" role="button">
      <span class="text-secondary small">content</span>
    </div>
  `
}

// Renders one node: its own row (skipped for the root fragment, which has
// no row of its own -- same as the old walk()) plus, nested inside the
// same wrapper, one container per array it owns (its slots, its children,
// its items). The wrapper itself carries `data-editor-item-id`, making it
// -- not the row -- the element editor_sortable_controller.js's
// `draggable: "[data-editor-item-id]"` option treats as one draggable
// unit, so dragging a node moves its whole subtree at once. @return an
// HTML string.
function renderNode(schema, node, depth, selectedId, selectedSlot, context) {
  if (node.kind === "fragment") {
    const containerId = `structure:${node.id}:children`
    return containerHtml(containerId, renderArray(schema, node.children || [], depth, selectedId, selectedSlot, context))
  }

  let html = rowHtml(node, depth, selectedId)
  const nextDepth = depth + 1

  // Advances the builder-map context for this node's own descendants --
  // entering a `component` node always resets to that component's own
  // :root level, and entering a nested builder_item (one whose own method
  // descriptor carries `nests`, e.g. navbar's left -> dropdown) advances
  // one level further. Mirrors editor/tree.js#visitWithContext exactly,
  // which the property panel already relies on for the same lookup against
  // one target id at a time.
  let childContext = context
  let descriptor = null
  if (node.kind === "component") {
    childContext = { componentName: node.name, level: "root" }
  } else if (node.kind === "builder_item") {
    descriptor = builderMethodDescriptor(schema, context, node.method)
    if (descriptor && descriptor.nests) {
      childContext = { componentName: context.componentName, level: descriptor.nests }
    }
  }

  if (node.kind === "component" && node.slots) {
    const meta = schema && schema.components && schema.components[node.name]
    const slotNames = (meta && meta.slots) || Object.keys(node.slots)
    slotNames.forEach((slotName) => {
      const children = node.slots[slotName] || []
      const containerId = `structure:${node.id}:slot__${slotName}`
      const inner = children.length === 0
        ? slotRowHtml(node.id, slotName, nextDepth, selectedSlot)
        : renderArray(schema, children, nextDepth + 1, selectedId, selectedSlot, childContext)
      html += containerHtml(containerId, inner)
    })
  }

  // A builder item whose own method takes a content block (`block:
  // "children"`) gets a real "children" container the exact same way a
  // row/column/fragment already does below -- EVEN WHEN the node itself
  // carries no `children` array yet: a freshly-added item
  // (editor_controller.js#addBuilderItem) has no `children` key at all
  // until the server's own Tree#normalize_builder_item adds one on the
  // first preview round-trip (docs/lib/tabler_ui/docs/editor/tree.rb) --
  // without this fallback the container silently disappeared from the
  // Structure pane until some unrelated edit happened to trigger a rebuild
  // against the by-then-normalized tree, which is the "no way to add
  // content" bug this whole fix exists for. `descriptor` is read straight
  // off the schema payload's own `block` field -- never a hardcoded list of
  // method names -- so this covers every current and future block:children
  // builder method (tabs.tab, accordion.item, settings_page.item, ...)
  // with the same code path.
  const acceptsChildren = !!(descriptor && descriptor.block === "children")
  if (Array.isArray(node.children) || acceptsChildren) {
    const kids = Array.isArray(node.children) ? node.children : []
    const containerId = `structure:${node.id}:children`
    const inner = acceptsChildren && kids.length === 0
      ? childrenRowHtml(node.id, nextDepth, selectedId)
      : renderArray(schema, kids, nextDepth, selectedId, selectedSlot, childContext)
    html += containerHtml(containerId, inner)
  }

  if (Array.isArray(node.items)) {
    html += containerHtml(`structure:${node.id}:items`, renderArray(schema, node.items, nextDepth, selectedId, selectedSlot, childContext))
  }

  return `<div class="docs-editor-structure-node" data-editor-item-id="${node.id}">${html}</div>`
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

  const isEmpty = tree.kind === "fragment" && (!tree.children || tree.children.length === 0)
  const html = renderNode(schema, tree, 0, selectedId, selectedSlot)

  if (isEmpty) {
    // The root container above is still rendered (empty) even here -- it
    // remains a real drop target for the very first node -- this message
    // just tells a mouse-only user what the Components tab is for.
    return `${html}<p class="text-secondary small mb-0 mt-2">Empty -- add something from the Components tab.</p>`
  }
  return html
}
