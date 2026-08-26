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

// Walks the tree tracking which component (and, inside a builder-style
// component, which BuilderMap "level") owns each builder_item -- needed by
// the property panel to look up a builder_item's own method definition in
// the schema payload (schema.components[name].builder[level][method]).
// `schema` only needs `.components[name].builder` -- see
// docs/lib/tabler_ui/docs/editor/schema.rb's "builder" shape.
function nestedLevelFor(schema, ctx, methodName) {
  const component = schema && schema.components && schema.components[ctx.componentName]
  const levelDef = component && component.builder && component.builder[ctx.level]
  const methodDef = levelDef && levelDef[methodName]
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

// --- structural mutation -- each returns a NEW tree -----------------------

export function removeNode(tree, id) {
  const clone = cloneTree(tree)
  const container = findContainer(clone, id)
  if (!container) return clone

  container.array.splice(container.index, 1)
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
