// Immutable operations over one file's design tree -- the client-side
// mirror of the node shapes docs/lib/tabler_ui/docs/editor/contract.rb
// documents ("Node kinds"). Every mutating function here clones the tree
// first and returns the clone; none of them ever mutates the tree object
// they were given. The server (Editor::Tree) is the only real validator --
// nothing here re-implements Contract's placement/limit rules, it only
// finds nodes and moves/edits them structurally. An illegal result (e.g. a
// column dropped directly under a fragment) is still handed to the preview
// endpoint like anything else and comes back as a reported error, exactly
// like every other "drop and report" case in the contract.

// --- id generation --------------------------------------------------------

// A client-generated opaque handle -- must match Contract::NODE_ID
// (/\A[a-z0-9_]{1,32}\z/). Timestamp + random + an incrementing counter is
// enough entropy that two ids generated in the same editor session never
// collide; Editor::Tree itself still rejects a genuine duplicate outright
// (defense in depth, not relied on here).
let counter = 0

export function generateId() {
  counter += 1
  const stamp = Date.now().toString(36).slice(-6)
  const rand = Math.random().toString(36).slice(2, 8)
  const id = `n${stamp}${rand}${counter}`.toLowerCase().replace(/[^a-z0-9_]/g, "")
  return id.slice(0, 32)
}

// --- cloning ---------------------------------------------------------------

// Every node value is JSON-shaped by construction (Contract's own
// "sanitize_generic_value" guarantee on the server side, and nothing on
// this side ever puts a function or a DOM reference into a node) --
// JSON round-tripping is a cheap, correct deep clone for this shape, and
// the tree is capped at Contract::LIMITS.nodes (500), so the cost is
// negligible.
export function cloneTree(tree) {
  return JSON.parse(JSON.stringify(tree))
}

// --- lookup ------------------------------------------------------------

// Every array of child nodes a node might carry: `children` (fragment,
// row, column), each value of `slots` (a slot-style component), and
// `items` (a builder-style component or a builder_item with block: :items).
function childArrays(node) {
  const arrays = []
  if (Array.isArray(node.children)) arrays.push(node.children)
  if (node.slots && typeof node.slots === "object") {
    Object.values(node.slots).forEach((arr) => { if (Array.isArray(arr)) arrays.push(arr) })
  }
  if (Array.isArray(node.items)) arrays.push(node.items)
  return arrays
}

// @return the node with this id anywhere in `tree` (a reference INTO
//   `tree`, not a copy), or null.
export function findNode(tree, id) {
  if (!tree) return null
  if (tree.id === id) return tree

  for (const arr of childArrays(tree)) {
    for (const child of arr) {
      const found = findNode(child, id)
      if (found) return found
    }
  }
  return null
}

// @return {array, index} for the array that directly contains the node
//   with this id (a reference INTO `tree`), or null if not found anywhere.
export function findContainer(tree, id) {
  if (!tree) return null

  for (const arr of childArrays(tree)) {
    const idx = arr.findIndex((n) => n.id === id)
    if (idx !== -1) return { array: arr, index: idx }

    for (const child of arr) {
      const found = findContainer(child, id)
      if (found) return found
    }
  }
  return null
}

// @param schema [Object, null] the /ui/editor/schema payload (or any subset
//   exposing `.components`) -- see docs/lib/tabler_ui/docs/editor/schema.rb's
//   "builder" shape.
// @param context [{componentName, level}, null] as returned by
//   #findNodeContext, or tracked by a caller doing its own tree walk (see
//   editor/structure.js, which needs this same lookup mid-walk rather than
//   for one targeted id).
// @param methodName [String] a builder_item's own `method`
// @return [Object, null] that method's descriptor
//   (schema.components[name].builder[level][method] -- `arg`/`block`/`nests`,
//   see schema.rb's own doc), or null when `context` is null (a builder_item
//   somehow reached outside any known component -- defensive, shouldn't
//   happen for a real tree) or the schema hasn't loaded yet.
export function builderMethodDescriptor(schema, context, methodName) {
  if (!context) return null
  const component = schema && schema.components && schema.components[context.componentName]
  const levelDef = component && component.builder && component.builder[context.level]
  return (levelDef && levelDef[methodName]) || null
}

// Walks the tree tracking which component (and, inside a builder-style
// component, which BuilderMap "level") owns each builder_item -- needed by
// the property panel to look up a builder_item's own method definition in
// the schema payload (schema.components[name].builder[level][method]).
// `schema` only needs `.components[name].builder` -- see
// docs/lib/tabler_ui/docs/editor/schema.rb's "builder" shape.
function nestedLevelFor(schema, ctx, methodName) {
  const methodDef = builderMethodDescriptor(schema, ctx, methodName)
  return methodDef && methodDef.nests ? methodDef.nests : null
}

function visitWithContext(schema, node, id, ctx) {
  if (!node) return null
  if (node.id === id) return { node, context: ctx }

  let childCtx = ctx
  if (node.kind === "component") {
    childCtx = { componentName: node.name, level: "root" }
  } else if (node.kind === "builder_item" && ctx) {
    const nested = nestedLevelFor(schema, ctx, node.method)
    if (nested) childCtx = { componentName: ctx.componentName, level: nested }
  }

  for (const arr of childArrays(node)) {
    for (const child of arr) {
      const found = visitWithContext(schema, child, id, childCtx)
      if (found) return found
    }
  }
  return null
}

// @return {node, context} where context is null for a node outside any
//   component, or {componentName, level} -- the level a builder_item's own
//   `method` should be looked up under in the schema payload. See the
//   property panel's builderItemFields (inspector.js) for the consumer.
export function findNodeContext(schema, tree, id) {
  return visitWithContext(schema, tree, id, null)
}

// @return the node that OWNS the container (children/slots/items) holding
//   the node with this id (a reference INTO `tree`) -- distinct from
//   findContainer, which returns the array and index but not the node that
//   array belongs to. null if `id` names the root itself (nothing owns the
//   root) or isn't found anywhere.
export function findParent(tree, id) {
  if (!tree) return null

  for (const arr of childArrays(tree)) {
    if (arr.some((child) => child.id === id)) return tree
    for (const child of arr) {
      const found = findParent(child, id)
      if (found) return found
    }
  }
  return null
}

// --- structural mutation -- each returns a NEW tree -----------------------

// Resolves the array `container` addresses on `parent`, creating it (and,
// for a slot, the `slots` object it lives in) if it doesn't exist yet --
// the shared plumbing under insertNode's own {slot, container} options,
// insertAt and moveNodeTo below. `container` is either the literal string
// "children"/"items", or "slot__<name>" for a named slot -- the same `<key>`
// half of the `structure:<nodeId>:<key>` container-id encoding
// editor/structure.js and editor_controller.js already share, so a caller
// holding that raw key never has to translate it into a separate {slot,
// container} shape first.
function resolveContainerArray(parent, container) {
  if (container.startsWith("slot__")) {
    const slotName = container.slice("slot__".length)
    parent.slots = parent.slots || {}
    parent.slots[slotName] = Array.isArray(parent.slots[slotName]) ? parent.slots[slotName] : []
    return parent.slots[slotName]
  }

  parent[container] = Array.isArray(parent[container]) ? parent[container] : []
  return parent[container]
}

// `schema` is optional (the /ui/editor/schema payload, or whatever subset
// of it exposes `kinds.column` -- see #rebalanceRow below): passing it
// lets removing a column from a row rebalance the row's remaining columns
// back to equal widths, exactly the "add a column" case #insertColumnBeside
// handles, just run in reverse. Omitting it (any OTHER caller of this
// generic remove-by-id function, or a caller with no schema loaded yet)
// degrades gracefully to the old behaviour -- splice and nothing else --
// rather than throwing, since #rebalanceRow itself no-ops with no schema
// to read a span vocabulary from.
export function removeNode(tree, id, schema) {
  const clone = cloneTree(tree)
  const container = findContainer(clone, id)
  if (!container) return clone

  // The row-rebalance question only ever applies when the node being
  // removed is itself a COLUMN sitting directly in a row's own `children`
  // (Tree::ROW_CONTAINER_KINDS: nothing else is ever stamped there) --
  // removing a heading, a card, or anything else just runs the plain
  // splice below exactly as before this feature existed. The signature is
  // captured from the FULL pre-removal array (the doomed column included)
  // for the same reason #insertColumnBeside captures its own signature
  // before splicing a new column in: "uniform" describes the row as the
  // editor left it, and the node about to disappear was as much a part of
  // that row a moment ago as any sibling staying behind.
  const parent = findParent(clone, id)
  const signature = (parent && parent.kind === "row") ? uniformSpan(container.array) : null

  container.array.splice(container.index, 1)

  // A gap is only worth closing if a column is actually left to stretch
  // into it -- an empty row (the last column just removed) has nothing to
  // rebalance, and #rebalanceRow/#evenSpans already no-op on a zero-length
  // array, but checking here reads clearer than relying on that.
  if (signature && container.array.length > 0) rebalanceRow(container.array, signature, schema)
  return clone
}

export function moveNode(tree, id, direction) {
  const clone = cloneTree(tree)
  const container = findContainer(clone, id)
  if (!container) return clone

  const { array, index } = container
  const target = direction === "up" ? index - 1 : index + 1
  if (target < 0 || target >= array.length) return clone

  const [item] = array.splice(index, 1)
  array.splice(target, 0, item)
  return clone
}

// Appends `node` as a child of `parentId`. `options.slot` targets a named
// slot on a slot-style component; `options.container` overrides the
// default "children" array (used to target "items" on a component/
// builder_item). Silently a no-op if `parentId` isn't found -- the
// controller is responsible for only ever calling this with a live
// selection.
export function insertNode(tree, parentId, node, options = {}) {
  const clone = cloneTree(tree)
  const parent = findNode(clone, parentId)
  if (!parent) return clone

  if (options.slot) {
    parent.slots = parent.slots || {}
    parent.slots[options.slot] = parent.slots[options.slot] || []
    parent.slots[options.slot].push(node)
    return clone
  }

  const containerKey = options.container || "children"
  parent[containerKey] = Array.isArray(parent[containerKey]) ? parent[containerKey] : []
  parent[containerKey].push(node)
  return clone
}

// Inserts `node` immediately after the node with `siblingId`, in whatever
// array currently holds it. Falls back to the tree's own root children if
// `siblingId` has no container (e.g. it names the root itself).
export function insertAfter(tree, siblingId, node) {
  const clone = cloneTree(tree)
  const container = findContainer(clone, siblingId)
  if (!container) {
    if (Array.isArray(clone.children)) clone.children.push(node)
    return clone
  }

  container.array.splice(container.index + 1, 0, node)
  return clone
}

// Inserts `node` into `parentId`'s `container` at `index`, clamped into
// range (below 0 clamps to 0; past the end clamps to the array's own
// length, i.e. appended). See resolveContainerArray above for what
// `container` addresses. No-op returning the original tree if `parentId`
// isn't found -- same "the controller is responsible for only ever calling
// this with a live target" contract insertNode already documents.
export function insertAt(tree, parentId, container, index, node) {
  const clone = cloneTree(tree)
  const parent = findNode(clone, parentId)
  if (!parent) return clone

  const array = resolveContainerArray(parent, container)
  const clamped = Math.max(0, Math.min(index, array.length))
  array.splice(clamped, 0, node)
  return clone
}

// Reparents/reorders `id` in one step: removes it from wherever it
// currently lives and inserts it into `parentId`'s `container` at `index`
// (see resolveContainerArray above for the `container` addressing).
//
// Same-container move: the node is removed BEFORE the destination array is
// resolved, so a same-container move resolves "source" and "destination"
// to the very same (already-shrunk) array object -- by the time the insert
// runs, every later sibling has already closed the gap the removal left,
// so splicing in at the raw `index` lands the node at exactly that final
// index with no separate arithmetic correction needed. Getting this wrong
// looks like resolving the destination array/index against a tree snapshot
// taken BEFORE the removal (or inserting before removing) -- either one
// leaves a downward move one slot short, because the still-present source
// node is still occupying a slot the destination index was counted against.
//
// No-op (returns a fresh clone of the ORIGINAL tree, not a mutated one with
// the node dropped on the floor) if `id` isn't found, or if `parentId`
// can't be found once `id` has been removed -- which also naturally covers
// dropping a node into its own subtree, since removing `id` takes that
// whole subtree, `parentId` included, out of the working tree with it.
export function moveNodeTo(tree, id, parentId, container, index) {
  const clone = cloneTree(tree)
  const source = findContainer(clone, id)
  if (!source) return clone

  const [node] = source.array.splice(source.index, 1)

  const parent = findNode(clone, parentId)
  if (!parent) return cloneTree(tree)

  const array = resolveContainerArray(parent, container)
  const clamped = Math.max(0, Math.min(index, array.length))
  array.splice(clamped, 0, node)
  return clone
}

// Wraps `targetId` and one OTHER node together into a new row of two
// columns, replacing `targetId` wherever it currently sits -- the compound
// structural op behind editor/drop_target.js's "wrap" descriptor (see that
// module's own header, "Four edges, one rule", for why a left/right edge
// band on an element that isn't already a row's own child means "build a
// row", not "insert a sibling"). `side` is "before" or "after": "before"
// puts the OTHER node's column first (the dragged node landed on
// `targetId`'s left edge), "after" puts `targetId`'s own column first
// (landed on its right edge) -- either way `targetId` keeps its own
// content, just moved one level deeper into its new column.
//
// `payload` is exactly one of the two shapes insertNode/moveNodeTo already
// take elsewhere in this file, not a third new one:
//   { newNode: <node> }  -- a palette drop: newNode is used as-is.
//   { moveId: <id> }     -- a canvas-node drag: the node with this id is
//                           removed from wherever it currently lives (which
//                           may be anywhere in the tree, not necessarily a
//                           sibling of targetId) and relocated into the new
//                           row instead.
//
// The OTHER node is resolved -- and, for a move, removed -- BEFORE
// `targetId`'s own container is looked up, same ordering #moveNodeTo's own
// header explains and for the same reason: if `payload.moveId` happens to
// be an earlier sibling of `targetId` in the very same array, finding
// `targetId`'s container/index only AFTER that removal means it's already
// counted against the post-removal shape, with no separate index
// correction needed for the gap the removal left.
//
// No-op (returns a fresh clone of the ORIGINAL tree) if `payload` names no
// node this function can resolve, or if `targetId` can no longer be found
// once the OTHER node has been removed -- which also naturally covers
// `payload.moveId === targetId` (dragging a node onto its own edge) and
// dragging an ancestor onto its own descendant's edge (removing the
// ancestor takes the descendant's whole subtree, `targetId` included, out
// of the working tree with it) -- the same "removal already made the
// destination unreachable" safety #moveNodeTo's own header documents.
//
// `columnSpan` is a plain {breakpointKey: value} object (e.g. {base: 6})
// applied to BOTH new columns as-is -- picking a value that makes visual
// sense for the grid is the CALLER's job (editor/drop_target.js reads it
// off the published span vocabulary -- see that module's own
// #defaultColumnSpan), not this one's: this file stays free of placement/
// limit rules, see its own header.
export function wrapInRow(tree, targetId, side, payload, columnSpan) {
  const clone = cloneTree(tree)

  let otherNode
  if (payload && payload.moveId) {
    const source = findContainer(clone, payload.moveId)
    if (!source) return clone
    ;[otherNode] = source.array.splice(source.index, 1)
  } else if (payload && payload.newNode) {
    otherNode = payload.newNode
  } else {
    return clone
  }

  const container = findContainer(clone, targetId)
  if (!container) return cloneTree(tree)

  const [targetNode] = container.array.splice(container.index, 1)

  const targetColumn = { kind: "column", id: generateId(), span: { ...columnSpan }, attrs: {}, children: [targetNode] }
  const otherColumn = { kind: "column", id: generateId(), span: { ...columnSpan }, attrs: {}, children: [otherNode] }
  const columns = side === "before" ? [otherColumn, targetColumn] : [targetColumn, otherColumn]
  const row = { kind: "row", id: generateId(), attrs: {}, children: columns }

  container.array.splice(container.index, 0, row)
  return clone
}

// Adds ONE new column, wrapping `payload`'s node, as a sibling of
// `columnId` inside `columnId`'s OWN row -- the compound structural op
// behind editor/drop_target.js's "column" descriptor (see that module's
// own header, the "Four edges, one rule" section, for the case this
// exists to serve: a hovered element that already lives inside a
// column-in-row. Joining the EXISTING row this way is preferred there over
// #wrapInRow's "build a brand new row", which would nest a second grid one
// level deeper instead of growing the one the user is already looking at).
// `side` is "before" or "after": "before" inserts the new column just
// ahead of `columnId` in its row's own `children`, "after" just behind it
// -- `columnId` itself is never moved or altered, only the array it lives
// in gains a new sibling.
//
// `payload` is the exact {newNode: <node>} / {moveId: <id>} shape
// #wrapInRow's own header documents -- a palette drop hands over a
// brand-new node as-is; a canvas-node drag names an existing node to
// relocate, removed from wherever it currently lives (which may or may not
// be a sibling column of the very same row -- either is handled the same
// way, see the ordering note below).
//
// The moved/new node is resolved -- and, for a move, removed from its old
// spot -- BEFORE `columnId`'s own container/index is looked up, the same
// ordering #moveNodeTo's and #wrapInRow's own headers explain and for the
// same reason: if `payload.moveId` names a node whose removal shifts
// `columnId`'s own position in its row's `children` (e.g. an earlier
// sibling column being relocated), resolving that position only AFTER the
// removal means it's already counted against the post-removal shape, with
// no separate index correction needed.
//
// No-op (returns a fresh clone of the ORIGINAL tree) if `payload` names no
// node this function can resolve; if `columnId` can no longer be found
// once the moved node has been removed (covers `payload.moveId ===
// columnId`, and dragging an ancestor onto its own descendant column's
// edge, the same "removal already made the destination unreachable"
// safety #moveNodeTo/#wrapInRow document); or if `columnId` doesn't
// actually live directly inside a row's own `children` (defensive only --
// editor/drop_target.js never resolves a "column" descriptor against
// anything else, since a column is only ever legal there in the first
// place).
//
// `columnSpan` is applied to the NEW column, exactly as given, as a
// starting point -- what happens to every OTHER column already in the row
// depends on whether they were all still uniform (#uniformSpan) the
// moment before this ran: if so, #rebalanceRow below rewrites the WHOLE
// row (existing columns and the new one alike) to equal widths that fit
// the grid, which is what makes `columnSpan`'s own value a starting point
// rather than the final answer for the new column too. If the existing
// columns disagreed with each other already (a hand-tuned 8/4 sidebar,
// say), #rebalanceRow declines to touch ANY of them, and `columnSpan` is
// exactly what the new column ends up with -- the original, pre-rebalance
// behaviour, preserved deliberately: silently rewriting a layout the user
// already customized is worse than leaving a fourth column to wrap.
// `schema` (the /ui/editor/schema payload, or a subset exposing
// `kinds.column`) is what #rebalanceRow reads the legal span vocabulary
// from -- optional, same graceful "no schema yet -> no rebalance" fallback
// #removeNode's own header describes.
export function insertColumnBeside(tree, columnId, side, payload, columnSpan, schema) {
  const clone = cloneTree(tree)

  let otherNode
  if (payload && payload.moveId) {
    const source = findContainer(clone, payload.moveId)
    if (!source) return clone
    ;[otherNode] = source.array.splice(source.index, 1)
  } else if (payload && payload.newNode) {
    otherNode = payload.newNode
  } else {
    return clone
  }

  const container = findContainer(clone, columnId)
  const parent = findParent(clone, columnId)
  if (!container || !parent || parent.kind !== "row") return cloneTree(tree)

  // Captured from the row's children BEFORE the new column is spliced in,
  // and deliberately never re-checked afterward: the new column's own span
  // is `columnSpan` (the caller's default, e.g. {base: 6}), which will
  // almost always differ from whatever width the EXISTING columns had
  // already settled on -- checking uniformity on the post-insert array
  // would see that mismatch and (wrongly) conclude the row just became
  // hand-tuned, when what actually happened is the opposite: the row was
  // uniform and is ABOUT to gain a column that hasn't been sized to match
  // yet, which is exactly the case #rebalanceRow exists to fix.
  const signature = uniformSpan(container.array)

  const newColumn = { kind: "column", id: generateId(), span: { ...columnSpan }, attrs: {}, children: [otherNode] }
  const index = side === "before" ? container.index : container.index + 1
  container.array.splice(index, 0, newColumn)

  if (signature) rebalanceRow(container.array, signature, schema)
  return clone
}

// --- row/column span rebalancing ---------------------------------------
//
// This trio (#numericSpanValues, #uniformSpan, #evenSpans) plus
// #rebalanceRow lives here, not in editor/drop_target.js, deliberately --
// this file's own header disclaims placement/limit RULES (which kind is
// legal where, how deep a tree may nest, how many nodes it may hold), and
// none of that is what this code decides. "Given a row now has N columns,
// what widths keep them summing to the grid's own total" is pure
// arithmetic over an array this file already owns and mutates (row.
// children), the same category of work #wrapInRow/#insertColumnBeside's
// own column-building already do -- not a judgment call about WHERE a
// drop may land, which stays entirely drop_target.js's job (it still picks
// the NEW column's starting span via its own #defaultColumnSpan, and still
// decides -- via the "column"/"wrap" split -- whether a drop joins an
// existing row at all). Keeping the arithmetic here also means
// #insertColumnBeside and #removeNode can share one implementation instead
// of two call sites each re-deriving it slightly differently.

// The grid's own legal numeric span values, read fresh off the schema
// payload every call rather than assumed -- `schema.kinds.column.
// spanValues` also carries the non-numeric "auto" entry (Contract::
// SPAN_VALUES), filtered out here since "auto" has no place in an even
// split. Sorted ascending so #evenSpans can treat the last entry as the
// grid's own total width and binary-search-by-filter down to the nearest
// legal value below any target width it computes.
function numericSpanValues(schema) {
  const columnMeta = schema && schema.kinds && schema.kinds.column
  const values = (columnMeta && columnMeta.spanValues) || []
  return values.filter((value) => typeof value === "number").sort((a, b) => a - b)
}

// True (and, then, the shared span object itself) iff every column in
// `columns` carries the exact same `span` value -- same breakpoint key(s),
// same width(s) at each. #wrapInRow and #insertColumnBeside always stamp
// every column they create with the identical `columnSpan` object, so a
// row where every column STILL agrees is, as far as this file can tell,
// one nobody has hand-tuned a single span on since. A row with as few as
// one column that disagrees (a user dragged just one sibling's width to 8,
// say) returns null for the WHOLE row -- deliberately not "rebalance the
// ones that still match" -- because a mixed row like that IS the
// customized layout #insertColumnBeside/#removeNode's own headers promise
// never to silently rewrite.
//
// @return the shared span object (reused as-is, not cloned -- callers only
//   ever read its keys/values, never mutate it) or null if `columns` is
//   empty, or its members disagree, or the (only) shared span is `{}`
//   (nothing to rebalance -- there's no breakpoint key to rewrite).
function uniformSpan(columns) {
  if (columns.length === 0) return null
  const first = columns[0].span || {}
  if (Object.keys(first).length === 0) return null

  const signature = JSON.stringify(first)
  const allMatch = columns.every((column) => JSON.stringify(column.span || {}) === signature)
  return allMatch ? first : null
}

// Splits the grid's own total width (the widest legal value #numericSpanValues
// returns -- Contract::SPAN_VALUES tops out at 12, but this reads that off
// the schema rather than hardcoding "12" here) as evenly as possible across
// `count` columns: each gets `floor(total / count)`, and the first
// `total % count` of them get one extra, so e.g. 5 columns of a 12-wide
// grid become 3,3,2,2,2 (sums to 12 -- as even as 5 divides into 12 -- not
// 2,2,2,2,2 with 2 units of grid left unused). Each computed width is then
// clamped down to the nearest value the schema's vocabulary actually
// contains (today's dense 1..12 run means this never bites, but nothing
// here assumes that stays true).
//
// @return an array of `count` widths, or null if `count` is more than the
//   grid can fit on one line at any width at all (more columns than the
//   grid's own total width -- e.g. 13 columns of a 12-wide grid can't each
//   get even a width of 1 and still sum to 12) -- the caller's cue to
//   leave every span exactly as it already was rather than emit a zero or
//   negative width; a wrapped row is the correct outcome there, not a bug
//   to paper over.
function evenSpans(count, values) {
  if (values.length === 0 || count <= 0) return null
  const total = values[values.length - 1]
  if (count > total) return null

  const base = Math.floor(total / count)
  const remainder = total % count
  const legalWidth = (target) => {
    const atOrBelow = values.filter((value) => value <= target)
    return atOrBelow.length > 0 ? atOrBelow[atOrBelow.length - 1] : values[0]
  }

  return Array.from({ length: count }, (_, i) => legalWidth(i < remainder ? base + 1 : base))
}

// Rewrites every column in `columns` (a row's own `children` array,
// already mutated by the caller to reflect the column count AFTER whatever
// insert/remove just happened -- #insertColumnBeside/#removeNode both call
// this only once the splice is already done) to an equal-width span, IN
// PLACE, keyed on whichever breakpoint(s) `signature` uses -- never a
// hardcoded "base" -- since #uniformSpan only ever hands back a real span
// object lifted off the row's own existing columns, whatever keys it
// happens to carry.
//
// `schema` feeds #numericSpanValues; if #evenSpans comes back null (no
// schema loaded yet, or `columns.length` can't fit the grid on one line --
// see that function's own header), this is a no-op and every column keeps
// the span it already had, same as if #rebalanceRow had never been called.
function rebalanceRow(columns, signature, schema) {
  const widths = evenSpans(columns.length, numericSpanValues(schema))
  if (!widths) return

  const keys = Object.keys(signature)
  columns.forEach((column, i) => {
    column.span = column.span || {}
    keys.forEach((key) => { column.span[key] = widths[i] })
  })
}

// Deep-clones the node with `id` -- generating a FRESH id (via generateId)
// for it and every descendant it carries, so the copy never collides with
// the original it was copied from -- and inserts the copy immediately
// after the original, in whatever array currently holds it.
//
// @return {tree, id} -- the new tree plus the copy's own freshly-generated
//   id, mirroring findNodeContext's {node, context} shape rather than the
//   plain-tree return every other mutator here uses, since a caller (e.g.
//   to select the duplicate afterwards) has no other way to learn that id.
export function duplicateNode(tree, id) {
  const clone = cloneTree(tree)
  const node = findNode(clone, id)
  if (!node) return { tree: clone, id: null }

  const copy = rekeyed(node)
  const container = findContainer(clone, id)
  if (!container) {
    // `id` names the root -- there's no sibling array to insert a copy
    // into, and duplicating the root wouldn't mean anything (a file has
    // exactly one). Clean no-op rather than guessing at a fallback.
    return { tree: clone, id: null }
  }

  container.array.splice(container.index + 1, 0, copy)
  return { tree: clone, id: copy.id }
}

// Recursively assigns a fresh id to `node` and every descendant it carries
// (children/slots/items -- the same traversal childArrays() walks), so a
// duplicated subtree never collides with the original it was copied from.
function rekeyed(node) {
  // Deep-cloning is needed because a shallow spread would leave options, args,
  // html, and other nested objects shared with the original node, so the copy
  // and original would not be independent of each other.
  const copy = { ...cloneTree(node), id: generateId() }
  if (Array.isArray(copy.children)) copy.children = copy.children.map(rekeyed)
  if (copy.slots && typeof copy.slots === "object") {
    const slots = {}
    Object.keys(copy.slots).forEach((key) => {
      slots[key] = Array.isArray(copy.slots[key]) ? copy.slots[key].map(rekeyed) : copy.slots[key]
    })
    copy.slots = slots
  }
  if (Array.isArray(copy.items)) copy.items = copy.items.map(rekeyed)
  return copy
}

// --- field mutation ---------------------------------------------------

// Generic path-based setter used by the property panel and in-canvas
// editing alike -- `path` is an array like ["content"], ["options",
// "title"], ["html", "root", "class"], ["span", "md"]. Creates
// intermediate objects as needed; `value === undefined` deletes the key
// instead of writing `undefined` into the tree (which the server would
// have to special-case).
export function setNodeValue(tree, id, path, value) {
  const clone = cloneTree(tree)
  const node = findNode(clone, id)
  if (!node || path.length === 0) return clone

  let target = node
  for (let i = 0; i < path.length - 1; i += 1) {
    const key = path[i]
    if (target[key] == null || typeof target[key] !== "object") target[key] = {}
    target = target[key]
  }

  const lastKey = path[path.length - 1]
  if (value === undefined) {
    delete target[lastKey]
  } else {
    target[lastKey] = value
  }
  return clone
}

export function getNodeValue(tree, id, path) {
  const node = findNode(tree, id)
  if (!node) return undefined

  let target = node
  for (const key of path) {
    if (target == null) return undefined
    target = target[key]
  }
  return target
}
