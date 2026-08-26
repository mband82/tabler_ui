// Pure geometry + placement math for "drag something onto the canvas" --
// both a palette item (a brand-new node) and an existing canvas node being
// reordered (editor_controller.js's #_onFrameDragStart / editor/dnd.js).
// Given the current tree, the schema payload, which stamped element the
// pointer is over (if any), where inside it, and (for a canvas-originated
// drag) which node is being moved, this resolves WHERE a drop would land
// if it happened right now -- nothing here writes to the DOM, touches
// dataTransfer, or holds state across calls. Every call is independent:
// the same inputs always produce the same descriptor.
//
// ## Three bands, not two
//
// A hovered element's own height is split into three vertical bands: the
// top BEFORE_FRACTION resolves to "insert before me", the bottom
// (1 - AFTER_FRACTION) resolves to "insert after me", and the middle band
// resolves to "into" -- landing INSIDE the element, when that means
// anything for its kind (see #resolveInto). When "into" doesn't mean
// anything (no container to land in, or a slot-style/builder-style
// component with no legal container available right now), the middle band
// falls back to whichever edge the pointer is closer to -- see
// #nearestEdge -- rather than resolving to nothing.
//
// ## Validity is advisory, never enforcement
//
// #resolveDropTarget's `valid`/`reason` (and, on a "chips" descriptor,
// each chip's own `valid`) exist to drive the drop cursor and how
// editor_controller.js paints the ghost/chips -- nothing else. The server
// (Editor::Tree) is the one real validator, and a tree this module calls
// "invalid" is still handed to the preview endpoint exactly like any other
// edit, coming back as a reported error the same way a bad manual property
// edit already does (see tree.js's own header, "the server ... is the only
// real validator"). Do not start enforcing these rules by refusing to
// perform a drop -- that would make this module a second, drifting copy of
// Editor::Tree's real placement logic. The one exception is dropping a
// node into its own descendant: `valid: false` there is still advisory
// (editor_controller.js still calls Tree.moveNodeTo unconditionally), but
// moveNodeTo's own contract already no-ops that case at the data layer
// (tree.js's own header on #moveNodeTo) -- this module's job is only to
// tell the ghost/chips to *look* refused, not to newly enforce anything.
//
// The placement vocabularies themselves (which kind is legal directly
// under which container) come from the schema payload's `kinds.placement`
// -- published by GET /ui/editor/schema specifically so this file never
// hardcodes its own copy of Tree::ROOT_KINDS / NON_ROW_CONTAINER_KINDS /
// ROW_CONTAINER_KINDS and can't drift from the server's real rules. The
// one deliberate exception is an `items` container: Editor::Tree's own
// normalize_items (docs/lib/tabler_ui/docs/editor/tree.rb) allows
// `builder_item` there and nothing else, a rule the published `placement`
// payload has no list for at all (it only publishes root/non-row/row
// container vocabularies). #resolveContainerChips never needs to consult
// one, though: it only ever proposes an `items`-container chip when
// `draggedKind === "builder_item"` in the first place (see that
// function), so the one kind it could ever offer is already the one kind
// that container accepts -- nothing here re-derives or duplicates Tree's
// rule, it just never has occasion to contradict it.
import { findNode, findContainer, findParent } from "controllers/tabler_ui/docs/editor/tree"

// The fraction of a hovered element's own height, measured from its own
// top edge, that the "insert before" band occupies; symmetrically, the
// "insert after" band starts at (1 - AFTER_FRACTION) and runs to the
// bottom. Everything between the two is the "into" band. Kept as named
// constants (rather than bare numbers) so editor_canvas.css or a future
// tuning pass has one place to read the same split this module enforces.
export const BEFORE_FRACTION = 0.25
export const AFTER_FRACTION = 0.75

// A dashed placeholder box's nominal height in the "append to an empty (or
// unhovered) root" case, where there is no sibling rect to size the ghost
// against -- editor_controller.js reads this rather than inventing its own
// number, so the two stay in sync without a second constant somewhere else.
export const ROOT_GHOST_HEIGHT = 28

// @param tree the current file's design tree (editor_controller.js
//   #_currentTree()), or null/undefined if no file is open.
// @param schema the /ui/editor/schema payload (editor_controller.js
//   #_schema), or null before it has loaded -- placement/limit checks are
//   skipped (permissive) rather than guessed at until it's available.
// @param hoveredNodeId the id of the stamped element under the pointer, or
//   null if the pointer is over no stamped element at all (empty canvas,
//   or dead space around the design).
// @param hoveredRect the hovered element's getBoundingClientRect(), or
//   null when hoveredNodeId is null.
// @param pointerY the drag's current clientY, in the same (frame-viewport)
//   coordinate space as hoveredRect.
// @param draggedKind the kind of the thing being dragged -- a palette
//   item's node kind ("row", "column", "heading", "text", "partial",
//   "component"), or, for a canvas-originated drag, the actual kind of the
//   node under the pointer at dragstart (which can also be "builder_item").
// @param draggedNodeId null for a palette drag (there is no existing node
//   yet); for a canvas-originated drag, the id of the node being moved --
//   used only to refuse landing inside that node's own subtree (see the
//   header above).
// @return {
//   parentId, container, index,     -- where Tree.insertAt/moveNodeTo would
//                                       place the node (container is
//                                       "children", "items", or
//                                       "slot__<name>"), or all null when
//                                       position is "chips" (there is no
//                                       single target -- see `chips` below)
//   position,                       -- "before" | "after" | "into" |
//                                       "append" | "chips"
//   anchorRect,                     -- the hoveredRect this was resolved
//                                       against, or null for "append"
//   insertionRect,                  -- {left, top, width} for the
//                                       insertion line -- set only for
//                                       "before"/"after", null otherwise
//   chips,                          -- [{label, parentId, container,
//                                       index, valid, reason}], set only
//                                       for position "chips", null
//                                       otherwise
//   valid, reason                   -- advisory only, see header. For
//                                       "chips", true iff at least one
//                                       chip is valid.
// }
export function resolveDropTarget({ tree, schema, hoveredNodeId, hoveredRect, pointerY, draggedKind, draggedNodeId = null }) {
  if (!tree) {
    return {
      parentId: null, container: null, index: 0, position: "append",
      anchorRect: null, insertionRect: null, chips: null, valid: false, reason: "no file is open"
    }
  }

  let target = null
  // hoveredNodeId === tree.id can't actually happen -- the root fragment
  // is never stamped with data-editor-node-id (editor_controller.js's own
  // task brief notes this) -- but guarding it costs nothing and keeps
  // #resolveAgainstElement from ever being asked to find "the root's own
  // container", which doesn't mean anything.
  if (hoveredNodeId && hoveredRect && hoveredNodeId !== tree.id) {
    target = resolveAgainstElement(tree, schema, hoveredNodeId, hoveredRect, pointerY, draggedKind, draggedNodeId)
  }
  if (!target) target = resolveAgainstRoot(tree)

  return { ...target, ...validateTarget(tree, schema, target, draggedKind, draggedNodeId) }
}

// --- geometry --------------------------------------------------------------

function bandFor(rect, pointerY) {
  const beforeEdge = rect.top + rect.height * BEFORE_FRACTION
  const afterEdge = rect.top + rect.height * AFTER_FRACTION
  if (pointerY < beforeEdge) return "before"
  if (pointerY > afterEdge) return "after"
  return "into"
}

// Used when the pointer is in the middle band but there's no "into" target
// to land in (see #resolveInto) -- falls back to whichever edge the
// pointer is nearer, so the middle band never resolves to nothing.
function nearestEdge(rect, pointerY) {
  const midpoint = rect.top + rect.height / 2
  return pointerY < midpoint ? "before" : "after"
}

function resolveAgainstElement(tree, schema, hoveredNodeId, hoveredRect, pointerY, draggedKind, draggedNodeId) {
  const container = findContainer(tree, hoveredNodeId)
  const parent = findParent(tree, hoveredNodeId)
  if (!container || !parent) return null

  const key = containerKeyFor(parent, container.array)
  if (!key) return null

  let band = bandFor(hoveredRect, pointerY)
  if (band === "into") {
    const hoveredNode = findNode(tree, hoveredNodeId)
    const into = resolveInto(tree, schema, hoveredNode, hoveredRect, draggedKind, draggedNodeId)
    if (into) return into
    band = nearestEdge(hoveredRect, pointerY) // no container to land in -- fall back to the nearer edge
  }

  const index = band === "before" ? container.index : container.index + 1

  return {
    parentId: parent.id,
    container: key,
    index,
    position: band,
    anchorRect: hoveredRect,
    insertionRect: {
      left: hoveredRect.left,
      top: band === "before" ? hoveredRect.top : hoveredRect.bottom,
      width: hoveredRect.width
    },
    chips: null
  }
}

// The middle band's "land inside the hovered element" case. Three kinds of
// hovered element, in the order this checks them:
//
//   1. row/column/fragment -- a plain container that takes children
//      directly, no chip menu needed: land at the end of its own
//      `children` array. (These three don't have their own schema entry
//      at all -- "component" is the only kind #resolveContainerChips ever
//      looks components up for -- so there's nothing to offer chips FOR
//      here even if we wanted to.)
//   2. a component with at least one legal chip target right now (an
//      empty slot, or -- only mid-reorder of an existing builder_item --
//      an existing left/right-shaped items container) -- see
//      #resolveContainerChips for the full rule. No single target exists
//      to return (the user has to pick a chip), so this returns a "chips"
//      descriptor instead of a parentId/container/index triple.
//   3. anything else (a component with nothing to offer, or a leaf kind
//      like heading/text/partial/builder_item that never accepts
//      children at all) -- no "into" landing exists; return null so the
//      caller falls back to the nearer edge.
function resolveInto(tree, schema, hoveredNode, hoveredRect, draggedKind, draggedNodeId) {
  if (!hoveredNode) return null

  if (["row", "column", "fragment"].includes(hoveredNode.kind)) {
    const children = Array.isArray(hoveredNode.children) ? hoveredNode.children : []
    return {
      parentId: hoveredNode.id,
      container: "children",
      index: children.length,
      position: "into",
      anchorRect: hoveredRect,
      insertionRect: null,
      chips: null
    }
  }

  const chips = legalChips(tree, schema, hoveredNode, draggedKind, draggedNodeId)
  if (chips.length === 0) return null

  return {
    parentId: null,
    container: null,
    index: null,
    position: "chips",
    anchorRect: hoveredRect,
    insertionRect: null,
    chips
  }
}

// The pointer is over no stamped element at all -- append to the file's
// root children. There is no sibling to draw an insertion line against
// (editor_controller.js falls back to sizing the ghost off the canvas
// element itself; see ROOT_GHOST_HEIGHT above).
function resolveAgainstRoot(tree) {
  const children = Array.isArray(tree.children) ? tree.children : []
  return {
    parentId: tree.id,
    container: "children",
    index: children.length,
    position: "append",
    anchorRect: null,
    insertionRect: null,
    chips: null
  }
}

// `arrayRef` is the exact array reference findContainer returned (a
// reference INTO the tree, per tree.js's own contract) -- so identity
// comparison against `parent`'s own children/items/each slot array
// unambiguously names which one it is, the same "slot__<name>" / "children"
// / "items" encoding tree.js's insertAt/moveNodeTo already use for
// `container`.
function containerKeyFor(parent, arrayRef) {
  if (parent.children === arrayRef) return "children"
  if (parent.items === arrayRef) return "items"
  if (parent.slots) {
    const slotName = Object.keys(parent.slots).find((key) => parent.slots[key] === arrayRef)
    if (slotName) return `slot__${slotName}`
  }
  return null
}

// --- chips (drop-into-container menu) --------------------------------

// One chip per container a "land inside" drop could legally use right
// now, for a hovered `component`-kind node. Two shapes (see this file's
// task-brief header, "Which containers to offer"):
//
//   * slot-style (schema `components[name].slots` is non-empty): one chip
//     per EMPTY slot -- a slot holds at most one node
//     (editor_controller.js#_handleStructureMove already enforces this),
//     so an occupied one isn't offered. A component with every slot
//     filled returns [] here, which #resolveInto above treats as "no
//     into target" and falls back to the edge bands.
//   * builder-style (schema `components[name].builder` present) AND the
//     thing being dragged is itself an existing `builder_item`
//     (`draggedKind === "builder_item"`): this is the one builder case
//     that's a genuine MOVE rather than a brand-new insert -- reordering
//     an existing builder_item among the `:root`-level methods that take
//     `block: "items"` (today, only navbar's `left`/`right`). One chip
//     per such method that already has a matching builder_item present
//     in the hovered component's own `items` array (there's no sensible
//     "create a left/right container from nothing" chip -- only an
//     EXISTING one is a move target). A palette drag (draggedKind is
//     never "builder_item" for one -- see palette.js, which only ever
//     drags row/column/heading/text/partial/component) or a foreign node
//     always gets [] here: only a builder_item is ever legal inside an
//     `items` array at all (this file's header), so nothing else could
//     ever land there.
//
// Plain row/column/fragment containers never reach this function --
// #resolveInto handles them directly, with no chip menu at all (see that
// function's own comment).
function resolveContainerChips(hoveredNode, schema, draggedKind) {
  if (!hoveredNode || hoveredNode.kind !== "component") return []
  const meta = schema && schema.components && schema.components[hoveredNode.name]
  if (!meta) return []

  const slots = Array.isArray(meta.slots) ? meta.slots : []
  if (slots.length > 0) {
    return slots
      .filter((slotName) => {
        const occupant = (hoveredNode.slots && hoveredNode.slots[slotName]) || []
        return occupant.length === 0
      })
      .map((slotName) => ({
        label: titleCase(slotName),
        parentId: hoveredNode.id,
        container: `slot__${slotName}`,
        index: 0
      }))
  }

  if (meta.builder && draggedKind === "builder_item") {
    const rootMethods = (meta.builder.root) || {}
    const itemsMethodNames = Object.keys(rootMethods).filter((name) => rootMethods[name].block === "items")
    if (itemsMethodNames.length === 0) return []

    const items = Array.isArray(hoveredNode.items) ? hoveredNode.items : []
    return itemsMethodNames
      .map((methodName) => {
        const child = items.find((n) => n.kind === "builder_item" && n.method === methodName)
        if (!child) return null // no existing left/right container to move into -- nothing to offer
        const childItems = Array.isArray(child.items) ? child.items : []
        return {
          label: titleCase(methodName),
          parentId: child.id,
          container: "items",
          index: childItems.length
        }
      })
      .filter((chip) => chip != null)
  }

  return []
}

function titleCase(name) {
  return name.charAt(0).toUpperCase() + name.slice(1)
}

// #resolveContainerChips's raw candidates, filtered down to the ones this
// drag could actually legally use right now: not inside the dragged
// node's own subtree (see this file's header on why that's advisory-only
// here), and -- for a slot chip -- kind-legal per the published
// `placement.nonRowContainerKinds` (an `items` chip skips this check
// entirely; see this file's header for why it doesn't need it). A chip
// that fails either check is dropped from the list outright rather than
// kept-but-disabled: the same "falls back to edge bands when there's
// nothing offerable" rule #resolveInto already applies to an empty chip
// list applies here too, not a new "disabled chip" UI concept.
function legalChips(tree, schema, hoveredNode, draggedKind, draggedNodeId) {
  const candidates = resolveContainerChips(hoveredNode, schema, draggedKind)
  const placement = schema && schema.kinds && schema.kinds.placement

  return candidates.filter((chip) => {
    if (draggedNodeId && isWithinSubtree(tree, draggedNodeId, chip.parentId)) return false
    if (chip.container === "items") return true // see resolveContainerChips's header
    if (!placement) return true
    return allowedKindsFor(tree, chip.parentId, chip.container, placement).includes(draggedKind)
  })
}

// @return true if `candidateId` is `ancestorId` itself, or anywhere in the
//   subtree it roots -- reuses tree.js's own findNode, called with the
//   ancestor's node (rather than the whole tree) as the search root, so no
//   separate subtree-walk needs writing here.
function isWithinSubtree(tree, ancestorId, candidateId) {
  const ancestor = findNode(tree, ancestorId)
  if (!ancestor) return false
  return findNode(ancestor, candidateId) != null
}

// --- placement / limits (advisory) ------------------------------------

// Validates a single-target descriptor (position "before"/"after"/"into"/
// "append") OR, for "chips", re-derives each chip's own valid/reason and
// folds them into one overall valid flag -- the two share every rule
// below (self-descendant, node/depth limits) except that a chip descriptor
// has no one parentId/container of its own to check kind-legality against
// (each chip already carried that from #legalChips, which builds the list
// pre-filtered) or depth against a single parent (each chip's own parentId
// can differ -- navbar's "Left" and "Right" chips are two different
// nodes). Kind-legality for a single-target descriptor is still checked
// here, same as before this file grew a middle band.
function validateTarget(tree, schema, target, draggedKind, draggedNodeId) {
  if (target.position === "chips") {
    const chips = (target.chips || []).map((chip) => ({
      ...chip,
      ...validateSingleTarget(tree, schema, chip, draggedKind, draggedNodeId, { skipKindCheck: true })
    }))
    return { chips, valid: chips.some((chip) => chip.valid), reason: chips.some((chip) => chip.valid) ? null : "nothing here can accept this drop" }
  }

  return validateSingleTarget(tree, schema, target, draggedKind, draggedNodeId, {})
}

function validateSingleTarget(tree, schema, target, draggedKind, draggedNodeId, { skipKindCheck }) {
  if (draggedNodeId && isWithinSubtree(tree, draggedNodeId, target.parentId)) {
    return { valid: false, reason: "cannot drop a node into its own descendant" }
  }

  const placement = schema && schema.kinds && schema.kinds.placement
  // No schema yet -- nothing to check against. Permissive rather than
  // blocking every drop until the schema fetch resolves (it's requested
  // in #connect and normally back well before a user could start a drag).
  if (!placement) return { valid: true, reason: null }

  // #legalChips already kind-filtered every chip candidate before this
  // ever runs (see that function) -- re-deriving allowedKindsFor a second
  // time here would just repeat work already done and, for an `items`
  // chip, would ask a question the published placement vocabularies can't
  // answer at all (this file's header).
  if (!skipKindCheck) {
    const allowedKinds = allowedKindsFor(tree, target.parentId, target.container, placement)
    if (!allowedKinds.includes(draggedKind)) {
      return { valid: false, reason: `a ${draggedKind} cannot be placed there` }
    }
  }

  const limits = schema.limits || {}
  if (typeof limits.nodes === "number" && countNodes(tree) + 1 > limits.nodes) {
    return { valid: false, reason: "the design already has the maximum number of nodes" }
  }

  if (typeof limits.depth === "number") {
    const parentDepth = target.parentId === tree.id ? 1 : depthOf(tree, target.parentId)
    if (parentDepth != null && parentDepth + 1 > limits.depth) {
      return { valid: false, reason: "that spot is nested past the maximum depth" }
    }
  }

  return { valid: true, reason: null }
}

// Mirrors Editor::Tree's own three allowed-kinds lists (ROOT_KINDS /
// NON_ROW_CONTAINER_KINDS / ROW_CONTAINER_KINDS -- see this file's header)
// entirely from the published `placement` vocabularies, never a hardcoded
// copy: the root container gets rootKinds, a `row` node's own "children"
// gets rowContainerKinds (this is the one place `column` is ever legal),
// and every other container (a non-row node's children, any slot, an
// items array) gets nonRowContainerKinds -- exactly Tree's own "everything
// ordinary except column" rule. (An `items` container is a partial
// exception to that last case -- see this file's header -- but every call
// site that resolves one skips this function for it; see
// #legalChips/#validateSingleTarget's `skipKindCheck`.)
function allowedKindsFor(tree, parentId, container, placement) {
  if (parentId === tree.id) return placement.rootKinds || []
  const parentNode = findNode(tree, parentId)
  if (!parentNode) return []
  if (container === "children" && parentNode.kind === "row") return placement.rowContainerKinds || []
  return placement.nonRowContainerKinds || []
}

function countNodes(node) {
  if (!node) return 0
  let total = 1
  if (Array.isArray(node.children)) total += node.children.reduce((sum, child) => sum + countNodes(child), 0)
  if (node.slots && typeof node.slots === "object") {
    total += Object.values(node.slots).reduce((sum, arr) => (
      sum + (Array.isArray(arr) ? arr.reduce((s, child) => s + countNodes(child), 0) : 0)
    ), 0)
  }
  if (Array.isArray(node.items)) total += node.items.reduce((sum, child) => sum + countNodes(child), 0)
  return total
}

// @return the depth (root = 1, same convention Editor::Tree.normalize
//   uses server-side) of the node with `id`, or null if not found.
function depthOf(node, id, depth = 1) {
  if (!node) return null
  if (node.id === id) return depth

  const arrays = []
  if (Array.isArray(node.children)) arrays.push(node.children)
  if (node.slots && typeof node.slots === "object") {
    Object.values(node.slots).forEach((arr) => { if (Array.isArray(arr)) arrays.push(arr) })
  }
  if (Array.isArray(node.items)) arrays.push(node.items)

  for (const arr of arrays) {
    for (const child of arr) {
      const found = depthOf(child, id, depth + 1)
      if (found != null) return found
    }
  }
  return null
}
