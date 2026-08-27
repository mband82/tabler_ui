// Builds the Inspector tab's markup -- the property panel -- from a
// selected node plus the /ui/editor/schema payload's per-option `control`
// values (docs/lib/tabler_ui/docs/editor/schema.rb's module doc, "Shape"
// section). Pure functions only -- the controller owns all DOM writes and
// event wiring, and is the one that rebuilds this panel, only on selection
// change (never mid-edit -- these inputs are read-only from JS otherwise,
// per this repo's CLAUDE.md rule on never re-rendering an element being
// typed into).
//
// Every control fires on "change", not "input" -- a <select>/<input
// type=checkbox>/<input type=number> already only fires "change" on a
// discrete interaction, and a text/textarea's "change" event fires once,
// on blur, when the value actually differs -- so rebuilding anything in
// response (the controller's applyField does) never fights a live caret
// the way a per-keystroke "input" listener would. That hazard is real only
// for the in-canvas contenteditable fields (see editor_controller.js).
//
// ## Foreign (cross-file) selections are read-only
//
// A canvas element can come from a `partial` node's referenced file, not
// the open one (editor_controller.js#_resolveNodeId / editor/workspace.js
// #findNodeAcrossWorkspace's own header). Such a node is selectable but
// never editable from here: every mutating action in this codebase
// (applyField, addColumn, addBuilderItem, ...) addresses a node by id
// against the OPEN file's tree, and a foreign id does not exist in that
// tree at all -- letting one of these controls fire would either silently
// no-op or, worse, act on whatever unrelated node the open tree happens to
// have at a colliding id. `readOnly`, threaded through every field-control
// builder below, is how that's enforced HERE: `disabled` on every input
// (a disabled control can't be focused or fire `change` at all -- no
// server-side or controller-side check is relied on beyond that), and the
// mutating "add"/"remove" BUTTONS (columns, builder items) omitted
// entirely rather than merely disabled, since those aren't tied to a
// single control's own `disabled` attribute the way a text/select field
// is. #foreignSelectionHtml is the one caller that passes `readOnly: true`;
// every other call renders the normal, editable panel exactly as before.
import { findNodeContext } from "controllers/tabler_ui/docs/editor/tree"
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"

// Set from the schema payload on every inspectorHtml() call. The schema is
// fetched once per page load and cached module-scope by editor/schema.js, so
// by the time anything below reads this it is populated. An empty list here
// therefore means the payload lost its "kinds" section, which schema_spec.rb
// guards against -- it is not a case to paper over with a literal fallback.
let KINDS = {}

const headingLevels = () => (KINDS.heading && KINDS.heading.levels) || []
const textTags = () => (KINDS.text && KINDS.text.tags) || []
const attrKeys = () => (KINDS.attrs && KINDS.attrs.keys) || []
const spanKeys = () => (KINDS.column && KINDS.column.spanKeys) || []
const spanValues = () => (KINDS.column && KINDS.column.spanValues) || []

// @param foreignSelection [{node, path, context}, null] set by
//   editor_controller.js#_selectFromCanvas when the current selection
//   resolved to a node living in a DIFFERENT file -- see this file's
//   header, "Foreign (cross-file) selections are read-only". Takes
//   priority over `nodeId`/`selectedSlot` (editor_controller.js never sets
//   both at once, but if it ever did, a foreign selection is the more
//   specific state -- it means a canvas click just happened).
export function inspectorHtml(schema, tree, nodeId, selectedSlot, foreignSelection) {
  KINDS = (schema && schema.kinds) || {}

  if (foreignSelection) return foreignSelectionHtml(schema, foreignSelection)

  if (!nodeId) {
    if (selectedSlot) return slotSelectionHtml(selectedSlot)
    return '<p class="text-secondary small mb-0">Select a node in the preview or the structure tree to edit its properties.</p>'
  }

  const found = tree && findNodeContext(schema, tree, nodeId)
  if (!found) return '<p class="text-secondary small mb-0">This node no longer exists.</p>'

  const { node, context } = found
  return nodeFieldsHtml(schema, node, context, false)
}

export function slotSelectionHtml(selectedSlot) {
  return `
    <p class="text-secondary small mb-0">
      Insertion target: slot "<strong>${escapeHtml(selectedSlot.slotName)}</strong>".
      Pick a layout item or component from the Components tab to add it here.
    </p>
  `
}

// The read-only view for a node that belongs to a DIFFERENT file (see this
// file's header). Reuses #nodeFieldsHtml -- the exact same field markup a
// LOCAL selection of the same kind would get -- rather than a hand-rolled
// summary, so the fields read identically to the editable ones, just
// disabled; only the banner above them is unique to this path.
//
// The "open file" button is literally the Explorer's own #selectFile
// Stimulus action (data-action + data-editor-path -- see
// editor_controller.js#selectFile/#Workspace.setOpen) -- not a second,
// inspector-only way to switch files.
function foreignSelectionHtml(schema, foreignSelection) {
  const { node, path, context } = foreignSelection

  return `
    <div class="alert alert-info py-2 px-3 mb-3 small">
      <div>This element belongs to <strong>${escapeHtml(path)}</strong> -- it was rendered here
      through a <code>partial</code> node and can't be edited from this file.</div>
      <button type="button" class="btn btn-sm btn-outline-info mt-2"
              data-action="click->tabler-ui--docs-editor#selectFile" data-editor-path="${escapeHtml(path)}">
        Open ${escapeHtml(path)}
      </button>
    </div>
    ${nodeFieldsHtml(schema, node, context, true)}
  `
}

// Shared by the normal (local, editable) path and the foreign (read-only)
// one above -- see #inspectorHtml / #foreignSelectionHtml. `readOnly`
// threads through to every field-control builder below.
function nodeFieldsHtml(schema, node, context, readOnly) {
  switch (node.kind) {
    case "heading": return headingFields(node, readOnly)
    case "text": return textFields(node, readOnly)
    case "row": return attrsFields(node, { withSpan: false, readOnly })
    case "column": return attrsFields(node, { withSpan: true, readOnly })
    case "partial": return partialFields(node, readOnly)
    case "component": return componentFields(schema, node, readOnly)
    case "builder_item": return builderItemFields(schema, node, context, readOnly)
    case "fragment": return '<p class="text-secondary small mb-0">The root container -- nothing to configure.</p>'
    default: return '<p class="text-secondary small mb-0">Unknown node kind.</p>'
  }
}

// --- fixed-shape node kinds ------------------------------------------------

// `disabled`/`action` below: `disabled` is applied unconditionally as an
// attribute string (empty when editable) rather than branching the whole
// control markup, and `action` -- the data-action wiring itself -- is
// dropped entirely when read-only, on top of `disabled`, not instead of
// it: a disabled control already can't fire "change" in any browser, but
// omitting the dead action attribute too means nothing here could ever
// look, from a glance at the markup, like it's wired to mutate a node it
// isn't allowed to.
function headingFields(node, readOnly) {
  const options = headingLevels().map((l) => (
    `<option value="${l}" ${node.level === l ? "selected" : ""}>${l}</option>`
  )).join("")
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  return `
    <h4 class="mb-2">Heading</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">level</label>
      <select class="form-select form-select-sm" ${action} ${disabled}
              data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["level"])}' data-editor-control="number">
        ${options}
      </select>
    </div>
    <div class="mb-2">
      <label class="form-label small mb-1">content</label>
      <textarea class="form-control form-control-sm" rows="2" ${action} ${disabled}
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["content"])}' data-editor-control="text"
      >${escapeHtml(node.content || "")}</textarea>
    </div>
  `
}

function textFields(node, readOnly) {
  const options = textTags().map((t) => (
    `<option value="${t}" ${node.tag === t ? "selected" : ""}>${t}</option>`
  )).join("")
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  return `
    <h4 class="mb-2">Text</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">tag</label>
      <select class="form-select form-select-sm" ${action} ${disabled}
              data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["tag"])}' data-editor-control="text">
        ${options}
      </select>
    </div>
    <div class="mb-2">
      <label class="form-label small mb-1">content</label>
      <textarea class="form-control form-control-sm" rows="2" ${action} ${disabled}
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["content"])}' data-editor-control="text"
      >${escapeHtml(node.content || "")}</textarea>
    </div>
  `
}

function attrsFields(node, { withSpan, readOnly }) {
  const attrs = node.attrs || {}
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`
  const attrInputs = attrKeys().map((key) => `
    <div class="mb-2">
      <label class="form-label small mb-1">${key}</label>
      <input type="text" class="form-control form-control-sm" ${action} ${disabled}
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["attrs", key])}' data-editor-control="text"
             value="${escapeHtml(attrs[key] || "")}">
    </div>
  `).join("")

  return `
    <h4 class="mb-2">${node.kind === "row" ? "Row" : "Column"}</h4>
    ${withSpan ? spanFields(node, readOnly) : ""}
    ${attrInputs}
  `
}

function spanFields(node, readOnly) {
  const span = node.span || {}
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`
  const cells = spanKeys().map((key) => {
    const options = spanValues().map((v) => (
      `<option value="${v}" ${String(span[key]) === String(v) ? "selected" : ""}>${v}</option>`
    )).join("")

    return `
      <div class="col-6 mb-2">
        <label class="form-label small mb-1">${key}</label>
        <select class="form-select form-select-sm" ${action} ${disabled}
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["span", key])}' data-editor-control="span">
          <option value="">--</option>
          ${options}
        </select>
      </div>
    `
  }).join("")

  return `<div class="row">${cells}</div>`
}

function partialFields(node, readOnly) {
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  return `
    <h4 class="mb-2">Partial</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">path</label>
      <input type="text" class="form-control form-control-sm" ${action} ${disabled}
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["path"])}' data-editor-control="text"
             value="${escapeHtml(node.path || "")}">
    </div>
  `
}

// --- component / builder_item -- schema-driven ------------------------

function componentFields(schema, node, readOnly) {
  if (!schema) return '<p class="text-secondary small mb-0">Loading component schema...</p>'

  const meta = schema.components && schema.components[node.name]
  if (!meta) return `<p class="text-secondary small mb-0">Unknown component '${escapeHtml(node.name)}'.</p>`

  const args = (meta.args || []).map((a) => (
    optionControlHtml(node, { name: a.name, control: a.control }, ["args"], node.args && node.args[a.name], readOnly)
  )).join("")
  const options = (meta.options || []).map((o) => optionAware(node, o, node.options && node.options[o.name], readOnly)).join("")
  // Suppressed entirely when read-only, not merely disabled -- these are
  // "add a new node" buttons, not a single control's own value; there is
  // no `disabled` attribute on a whole action like there is on an input.
  const builderButtons = (!readOnly && meta.builder && meta.builder.root) ? builderAddButtons(node, meta.builder.root, "root") : ""

  return `
    <h4 class="mb-1">${escapeHtml(meta.title)}</h4>
    ${meta.description ? `<p class="text-secondary small">${escapeHtml(meta.description)}</p>` : ""}
    ${args}
    ${options}
    ${builderButtons}
    ${htmlPartsHtml(node, meta.htmlParts, readOnly)}
    ${unsupportedHtml(meta.unsupported)}
  `
}

function builderItemFields(schema, node, context, readOnly) {
  if (!schema) return '<p class="text-secondary small mb-0">Loading component schema...</p>'
  if (!context) return '<p class="text-secondary small mb-0">Could not determine this item\'s owning component.</p>'

  const component = schema.components && schema.components[context.componentName]
  const levelDef = component && component.builder && component.builder[context.level]
  const methodDef = levelDef && levelDef[node.method]
  if (!methodDef) return `<p class="text-secondary small mb-0">Unknown builder method '${escapeHtml(node.method)}'.</p>`

  const argHtml = methodDef.arg
    ? optionControlHtml(node, { name: methodDef.arg.name, control: methodDef.arg.control }, ["args"],
                         node.args && node.args[methodDef.arg.name], readOnly)
    : ""
  const options = (methodDef.options || []).map((o) => optionAware(node, o, node.options && node.options[o.name], readOnly)).join("")
  const nestedButtons = (!readOnly && methodDef.nests && component.builder[methodDef.nests])
    ? builderAddButtons(node, component.builder[methodDef.nests], methodDef.nests)
    : ""

  return `
    <h4 class="mb-2">${escapeHtml(context.componentName)}#${escapeHtml(node.method)}</h4>
    ${argHtml}
    ${options}
    ${nestedButtons}
    ${htmlPartsHtml(node, methodDef.htmlParts, readOnly)}
    ${unsupportedHtml(methodDef.unsupported)}
  `
}

function builderAddButtons(node, levelDef, level) {
  const buttons = Object.keys(levelDef).map((method) => `
    <button type="button" class="btn btn-sm btn-outline-secondary me-1 mb-1"
            data-action="click->tabler-ui--docs-editor#addBuilderItem"
            data-editor-node-id="${node.id}" data-editor-method="${escapeHtml(method)}" data-editor-level="${escapeHtml(level)}">
      + ${escapeHtml(method)}
    </button>
  `).join("")

  return `<h5 class="mt-3 mb-1">Add item</h5><div>${buttons}</div>`
}

function optionAware(node, option, currentValue, readOnly) {
  if (option.control === "columns") return columnsControlHtml(node, option, currentValue, readOnly)
  if (option.control === "rows") return rowsControlHtml(node, option, currentValue, readOnly)
  if (option.control === "sort_url") return sortUrlControlHtml(node, option, currentValue, readOnly)
  // table's own :sort ("{key:, dir:}") is a plain Hash -- Schema.control_for
  // resolves it to the generic "json" escape hatch same as any other Hash
  // option (STRUCTURED_TYPE_SETS), so this isn't a dedicated
  // DECLARATIVE_CONTROLS entry the way :columns/:data/:sort_url are; it's
  // narrowed by (component name, option name) right here instead, the way
  // #columnSortFieldHtml's own "Sortable" checkbox is. table's :filter is
  // the same "Hash" type string and deliberately NOT special-cased here --
  // it has no declarative shape this control could build a form from, so
  // it stays on the raw-JSON fallback.
  if (option.control === "json" && node.name === "table" && option.name === "sort") {
    return sortControlHtml(node, option, currentValue, readOnly)
  }
  return optionControlHtml(node, option, ["options"], currentValue, readOnly)
}

function fieldWrap(option, controlHtml) {
  const desc = option.description ? `<div class="text-secondary small">${escapeHtml(option.description)}</div>` : ""
  return `
    <div class="mb-2">
      <label class="form-label small mb-1">${escapeHtml(option.name)}</label>
      ${controlHtml}
      ${desc}
    </div>
  `
}

// `symbol` (Schema's own EnumMap.symbol? flag) needs no special handling
// here -- the server's own Editor::Tree#sanitize_option_value already
// looks the option up in EnumMap and converts to a real Symbol there,
// regardless of what shape the client sent, so a plain String value is all
// this ever needs to produce.
function optionControlHtml(node, option, pathPrefix, currentValue, readOnly) {
  const path = JSON.stringify([...pathPrefix, option.name])
  const value = currentValue === undefined ? "" : currentValue
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`
  const common = `data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="${option.control}"`

  switch (option.control) {
    case "checkbox":
      return `
        <div class="mb-2 form-check">
          <input type="checkbox" class="form-check-input" id="opt-${node.id}-${escapeHtml(option.name)}" ${common} ${disabled}
                 ${action} ${value === true ? "checked" : ""}>
          <label class="form-check-label" for="opt-${node.id}-${escapeHtml(option.name)}">${escapeHtml(option.name)}</label>
          ${option.description ? `<div class="text-secondary small">${escapeHtml(option.description)}</div>` : ""}
        </div>
      `
    case "number":
      return fieldWrap(option, `
        <input type="number" class="form-control form-control-sm" ${common} ${disabled}
               ${action} value="${value === "" ? "" : escapeHtml(value)}">
      `)
    case "select":
      return fieldWrap(option, selectControlHtml(option, common, value, readOnly))
    case "json":
      return fieldWrap(option, `
        <textarea class="form-control form-control-sm" rows="3" ${common} ${disabled}
                  ${action}
        >${value === "" ? "" : escapeHtml(JSON.stringify(value, null, 2))}</textarea>
      `)
    case "text":
    default:
      return fieldWrap(option, `
        <input type="text" class="form-control form-control-sm" ${common} ${disabled}
               ${action} value="${escapeHtml(value)}">
      `)
  }
}

function selectControlHtml(option, common, value, readOnly) {
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`
  const options = (option.values || []).map((v) => (
    `<option value="${escapeHtml(v)}" ${String(value) === String(v) ? "selected" : ""}>${escapeHtml(v)}</option>`
  )).join("")

  return `
    <select class="form-select form-select-sm" ${common} ${disabled} ${action}>
      <option value="">(default)</option>
      ${options}
    </select>
  `
}

function rowsControlHtml(node, option, currentValue, readOnly) {
  const value = currentValue === undefined ? [] : currentValue
  const path = JSON.stringify(["options", option.name])
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  return fieldWrap(option, `
    <textarea class="form-control form-control-sm" rows="4"
              data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="json" ${disabled}
              ${action}
    >${escapeHtml(JSON.stringify(value, null, 2))}</textarea>
    <div class="text-secondary small">Each row's keys should match a column's key.</div>
  `)
}

function columnsControlHtml(node, option, currentValue, readOnly) {
  const columns = Array.isArray(currentValue) ? currentValue : []
  const fields = option.fields || []
  const rows = columns.map((col, index) => columnRowHtml(node, option.name, fields, col, index, readOnly)).join("")
  // Suppressed entirely when read-only -- see #componentFields' own note on
  // `builderButtons` for why an action button, unlike a field control, has
  // no `disabled` middle ground here.
  const addButton = readOnly ? "" : `
    <button type="button" class="btn btn-sm btn-outline-secondary mt-1"
            data-action="click->tabler-ui--docs-editor#addColumn"
            data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(option.name)}">
      Add column
    </button>
  `

  return `
    <div class="mb-3">
      <label class="form-label small mb-1">${escapeHtml(option.name)}</label>
      <div>${rows}</div>
      ${addButton}
    </div>
  `
}

// `sort` is rendered separately from the other COLUMN_FIELDS entries
// (below) rather than through the same plain-text-input loop: it's a
// checkbox-plus-conditional-text-field pairing, not a bare text box, so it
// needs its own markup. Every OTHER field (key/label/class today) stays on
// the generic loop -- this function has no opinion about what those are,
// it just knows to skip whichever one is named "sort".
function columnRowHtml(node, optionName, fields, col, index, readOnly) {
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#updateColumnField"`
  const plainFields = fields.filter((f) => f.name !== "sort")
  const inputs = plainFields.map((f) => {
    const value = col && col[f.name] != null ? col[f.name] : ""
    return `
      <input type="text" class="form-control form-control-sm mb-1" ${disabled}
             placeholder="${escapeHtml(f.name)}${f.required ? " *" : ""}" value="${escapeHtml(value)}"
             ${action}
             data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}"
             data-editor-index="${index}" data-editor-field="${escapeHtml(f.name)}">
    `
  }).join("")

  const sortField = fields.some((f) => f.name === "sort")
    ? columnSortFieldHtml(node, optionName, col, index, readOnly)
    : ""

  const removeButton = readOnly ? "" : `
    <button type="button" class="btn btn-sm btn-outline-danger"
            data-action="click->tabler-ui--docs-editor#removeColumn"
            data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}" data-editor-index="${index}">
      Remove
    </button>
  `

  return `
    <div class="border rounded p-2 mb-2">
      ${inputs}
      ${sortField}
      ${removeButton}
    </div>
  `
}

// A "Sortable" checkbox plus, only while checked, a text field carrying
// the actual sort key -- pre-filled with the column's own `key` the
// moment the box is ticked (see editor_controller.js#toggleColumnSort),
// but freely editable afterward: Table::Component compares `sort:`
// against the table-level `sort[:key]` as a plain String (#sorted?), with
// no requirement that it equal the column's own `key` -- a column can
// render one field and sort by another. The checkbox itself fires
// #toggleColumnSort (a dedicated action, not #updateColumnField -- it
// has to decide what value to seed, not just copy `el.value` across),
// while the text field, once shown, is an ordinary #updateColumnField
// input exactly like `label`/`class` above.
function columnSortFieldHtml(node, optionName, col, index, readOnly) {
  const disabled = readOnly ? "disabled" : ""
  const checkboxAction = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#toggleColumnSort"`
  const textAction = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#updateColumnField"`
  const sortKey = col && col.sort != null ? col.sort : null
  const checkboxId = `docs-editor-col-sort-${node.id}-${index}`

  const keyInput = sortKey != null ? `
    <input type="text" class="form-control form-control-sm mb-1" ${disabled} ${textAction}
           placeholder="sort key" value="${escapeHtml(sortKey)}"
           data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}"
           data-editor-index="${index}" data-editor-field="sort">
  ` : ""

  return `
    <div class="form-check mb-1">
      <input type="checkbox" class="form-check-input" id="${checkboxId}" ${disabled} ${checkboxAction}
             data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}"
             data-editor-index="${index}" ${sortKey != null ? "checked" : ""}>
      <label class="form-check-label" for="${checkboxId}">Sortable</label>
    </div>
    ${keyInput}
  `
}

// --- table-level :sort ("{key:, dir:}") --------------------------------

// The dropdown lists only columns the table itself just made sortable
// (col.sort present, via #columnSortFieldHtml's checkbox above) -- pulled
// straight from this same node's own `columns` option, already in hand as
// `node.options.columns`, rather than a second server round-trip; see this
// file's #optionAware for why this is narrowed to exactly (table, sort)
// rather than a generic Hash-typed control. Selecting "(unsorted)" clears
// only the `key` sub-field (a plain #applyField write, same mechanism as
// every other nested path in this file) -- Table::Component#normalize_sort
// already treats a keyless sort: Hash as unsorted, so that alone is enough
// to reach the default state; "Clear sort" (#clearTableSort) goes further
// and drops the whole `sort:` option, for a clean export with no stray
// Hash left behind.
function sortControlHtml(node, option, currentValue, readOnly) {
  const columns = (node.options && Array.isArray(node.options.columns)) ? node.options.columns : []
  const sortableColumns = columns.filter((c) => c && c.sort != null && c.sort !== "")
  const value = (currentValue && typeof currentValue === "object") ? currentValue : {}
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  if (sortableColumns.length === 0) {
    return fieldWrap(option, `
      <p class="text-secondary small mb-0">Mark a column "Sortable" above to enable sorting here.</p>
    `)
  }

  const keyOptions = sortableColumns.map((col) => {
    const label = col.label || col.key || col.sort
    return `<option value="${escapeHtml(col.sort)}" ${String(value.key) === String(col.sort) ? "selected" : ""}>${escapeHtml(label)}</option>`
  }).join("")

  const dir = value.dir === "desc" ? "desc" : "asc"

  const clearButton = readOnly ? "" : `
    <button type="button" class="btn btn-sm btn-outline-secondary mt-1"
            data-action="click->tabler-ui--docs-editor#clearTableSort"
            data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(option.name)}">
      Clear sort
    </button>
  `

  return fieldWrap(option, `
    <select class="form-select form-select-sm mb-1" ${action} ${disabled}
            data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["options", option.name, "key"])}'
            data-editor-control="text">
      <option value="">(unsorted)</option>
      ${keyOptions}
    </select>
    <select class="form-select form-select-sm" ${action} ${disabled}
            data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["options", option.name, "dir"])}'
            data-editor-control="text">
      <option value="asc" ${dir === "asc" ? "selected" : ""}>ascending</option>
      <option value="desc" ${dir === "desc" ? "selected" : ""}>descending</option>
    </select>
    ${clearButton}
  `)
}

// --- table-level :sort_url (declarative, two modes) ---------------------

// Mode is a pair of buttons, not a passive <select> defaulted to "simple"
// -- a <select> already showing "simple" without the user ever touching it
// would look configured while `options.sort_url` stays entirely unset,
// which is exactly the gap #setSortUrlMode exists to avoid: clicking EITHER
// button (even the one that already looks active) is what actually writes
// a real value -- `{mode:, sortParam: "sort", dirParam: "dir", ...}` -- into
// the tree, and only that write makes the fields below appear at all.
// Once set, switching modes preserves both sides' fields (see
// #setSortUrlMode's own comment) so bouncing back and forth never loses
// what was typed on either one.
function sortUrlControlHtml(node, option, currentValue, readOnly) {
  const value = (currentValue && typeof currentValue === "object") ? currentValue : null
  const mode = value && value.mode === "pattern" ? "pattern" : "simple"
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  const modeButton = (targetMode, label) => {
    const active = value && mode === targetMode
    const classes = active ? "btn-primary" : "btn-outline-secondary"
    if (readOnly) return `<button type="button" class="btn btn-sm ${classes}" disabled>${label}</button>`
    return `
      <button type="button" class="btn btn-sm ${classes}"
              data-action="click->tabler-ui--docs-editor#setSortUrlMode"
              data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(option.name)}"
              data-editor-mode="${targetMode}">
        ${label}
      </button>
    `
  }
  const modeButtons = `<div class="btn-group mb-2" role="group">${modeButton("simple", "Simple")}${modeButton("pattern", "Custom pattern")}</div>`

  if (!value) {
    return fieldWrap(option, `
      ${modeButtons}
      <p class="text-secondary small mb-0">Not configured -- pick a mode to build sortable header links.</p>
    `)
  }

  const fields = mode === "pattern"
    ? patternSortUrlFieldsHtml(node, option.name, value, disabled, action)
    : simpleSortUrlFieldsHtml(node, option.name, value, disabled, action)

  const clearButton = readOnly ? "" : `
    <button type="button" class="btn btn-sm btn-outline-danger mt-1"
            data-action="click->tabler-ui--docs-editor#clearSortUrl"
            data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(option.name)}">
      Clear
    </button>
  `

  return fieldWrap(option, `${modeButtons}${fields}${clearButton}`)
}

// Three plain text fields -- path, sort parameter name, direction
// parameter name -- matching SortUrl.pattern_for's own simple-mode formula
// exactly (`"#{path}?#{sortParam}={key}&#{dirParam}={dir}"`).
// `sortParam`/`dirParam` default to "sort"/"dir", the conventional names,
// and `path` defaults to "/" -- all three pre-written into the tree the
// moment simple mode is picked (see #setSortUrlMode /
// DEFAULT_SIMPLE_SORT_URL in editor_controller.js) rather than merely shown
// as an input placeholder: a placeholder is never actually submitted, and
// Tree#valid_simple_sort_url? requires all three fields present AND
// non-empty, so leaving any one of them blank until the user typed
// something would silently fail validation the moment "Simple" was picked
// -- the exact self-undoing-control failure this whole feature had to be
// fixed for once already (see #toggleColumnSort's header in
// editor_controller.js). `path` is a placeholder value in the ordinary
// sense -- a stand-in a user is expected to replace with their own route --
// but it is real, present data as far as Tree is concerned from the
// instant this field renders.
function simpleSortUrlFieldsHtml(node, optionName, value, disabled, action) {
  const field = (key, label, placeholder) => `
    <div class="mb-2">
      <label class="form-label small mb-1">${label}</label>
      <input type="text" class="form-control form-control-sm" ${disabled} ${action}
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["options", optionName, key])}'
             data-editor-control="text" placeholder="${placeholder}" value="${escapeHtml(value[key] || "")}">
    </div>
  `

  return `
    ${field("path", "path", "/users")}
    ${field("sortParam", "sort parameter", "sort")}
    ${field("dirParam", "direction parameter", "dir")}
  `
}

// One text field taking a raw "{key}"/"{dir}" pattern -- the exact string
// SortUrl.pattern_for passes straight through unchanged for pattern mode.
// Tree#valid_pattern_sort_url? rejects (with a visible error -- see this
// file's own header on #_renderErrors surfacing the preview response's
// `errors`) a pattern missing either placeholder -- which is exactly why
// #setSortUrlMode / DEFAULT_PATTERN_SORT_URL pre-writes "/{key}/{dir}" the
// moment "Custom pattern" is picked, rather than leaving this field's HTML
// `placeholder` attribute (below) as the only thing showing the required
// shape: an attribute placeholder is never actually submitted, so an empty
// real value would fail that same validation on the very first round-trip.
// No client-side validation is duplicated here beyond what the input's own
// placeholder text hints at for whatever the user types next.
function patternSortUrlFieldsHtml(node, optionName, value, disabled, action) {
  return `
    <div class="mb-2">
      <label class="form-label small mb-1">pattern</label>
      <input type="text" class="form-control form-control-sm" ${disabled} ${action}
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["options", optionName, "pattern"])}'
             data-editor-control="text" placeholder="/reports/sorted/{key}/{dir}"
             value="${escapeHtml(value.pattern || "")}">
      <div class="text-secondary small">Must contain both {key} and {dir}.</div>
    </div>
  `
}

function htmlPartsHtml(node, parts, readOnly) {
  if (!parts || parts.length === 0) return ""
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#applyField"`

  const rows = parts.map((part) => {
    const value = (node.html && node.html[part]) || {}
    const path = JSON.stringify(["html", part])
    return `
      <div class="mb-2">
        <label class="form-label small mb-1">html: ${escapeHtml(part)}</label>
        <textarea class="form-control form-control-sm" rows="2" ${disabled}
                  data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="json"
                  ${action}
        >${escapeHtml(JSON.stringify(value, null, 2))}</textarea>
      </div>
    `
  }).join("")

  return `<details class="mt-3"><summary class="text-secondary small">HTML hooks</summary>${rows}</details>`
}

function unsupportedHtml(list) {
  if (!list || list.length === 0) return ""

  const rows = list.map((u) => (
    `<li><code>${escapeHtml(u.name)}</code> <span class="text-secondary">(${escapeHtml(u.reason)})</span>` +
    `${u.description ? ` -- ${escapeHtml(u.description)}` : ""}</li>`
  )).join("")

  return `<h5 class="mt-3">Not editable here</h5><ul class="small text-secondary mb-0">${rows}</ul>`
}
