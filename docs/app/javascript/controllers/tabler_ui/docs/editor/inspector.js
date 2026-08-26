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

function columnRowHtml(node, optionName, fields, col, index, readOnly) {
  const disabled = readOnly ? "disabled" : ""
  const action = readOnly ? "" : `data-action="change->tabler-ui--docs-editor#updateColumnField"`
  const inputs = fields.map((f) => {
    const value = col && col[f.name] != null ? col[f.name] : ""
    return `
      <input type="text" class="form-control form-control-sm mb-1" ${disabled}
             placeholder="${escapeHtml(f.name)}${f.required ? " *" : ""}" value="${escapeHtml(value)}"
             ${action}
             data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}"
             data-editor-index="${index}" data-editor-field="${escapeHtml(f.name)}">
    `
  }).join("")

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
      ${removeButton}
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
