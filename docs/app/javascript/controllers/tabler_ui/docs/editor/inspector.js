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
// ## The non-component kinds' vocabularies
//
// Heading levels, text tags, row/column attribute keys and a column's span
// keys/values are Contract-level constants living on the server
// (docs/lib/tabler_ui/docs/editor/contract.rb). They reach this file through
// the schema payload's "kinds" section (Schema#kinds_payload) rather than
// being restated here: a hand-mirrored copy with nothing asserting it still
// matches Contract is precisely the drift this codebase writes anti-rot
// specs to prevent, and it would rot the moment Contract gained a text tag
// or a breakpoint.
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

export function inspectorHtml(schema, tree, nodeId, selectedSlot) {
  KINDS = (schema && schema.kinds) || {}

  if (!nodeId) {
    if (selectedSlot) return slotSelectionHtml(selectedSlot)
    return '<p class="text-secondary small mb-0">Select a node in the preview or the structure tree to edit its properties.</p>'
  }

  const found = tree && findNodeContext(schema, tree, nodeId)
  if (!found) return '<p class="text-secondary small mb-0">This node no longer exists.</p>'

  const { node, context } = found
  switch (node.kind) {
    case "heading": return headingFields(node)
    case "text": return textFields(node)
    case "row": return attrsFields(node, { withSpan: false })
    case "column": return attrsFields(node, { withSpan: true })
    case "partial": return partialFields(node)
    case "component": return componentFields(schema, node)
    case "builder_item": return builderItemFields(schema, node, context)
    case "fragment": return '<p class="text-secondary small mb-0">The root container -- nothing to configure.</p>'
    default: return '<p class="text-secondary small mb-0">Unknown node kind.</p>'
  }
}

export function slotSelectionHtml(selectedSlot) {
  return `
    <p class="text-secondary small mb-0">
      Insertion target: slot "<strong>${escapeHtml(selectedSlot.slotName)}</strong>".
      Pick a layout item or component from the Components tab to add it here.
    </p>
  `
}

// --- fixed-shape node kinds ------------------------------------------------

function headingFields(node) {
  const options = headingLevels().map((l) => (
    `<option value="${l}" ${node.level === l ? "selected" : ""}>${l}</option>`
  )).join("")

  return `
    <h4 class="mb-2">Heading</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">level</label>
      <select class="form-select form-select-sm" data-action="change->tabler-ui--docs-editor#applyField"
              data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["level"])}' data-editor-control="number">
        ${options}
      </select>
    </div>
    <div class="mb-2">
      <label class="form-label small mb-1">content</label>
      <textarea class="form-control form-control-sm" rows="2" data-action="change->tabler-ui--docs-editor#applyField"
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["content"])}' data-editor-control="text"
      >${escapeHtml(node.content || "")}</textarea>
    </div>
  `
}

function textFields(node) {
  const options = textTags().map((t) => (
    `<option value="${t}" ${node.tag === t ? "selected" : ""}>${t}</option>`
  )).join("")

  return `
    <h4 class="mb-2">Text</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">tag</label>
      <select class="form-select form-select-sm" data-action="change->tabler-ui--docs-editor#applyField"
              data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["tag"])}' data-editor-control="text">
        ${options}
      </select>
    </div>
    <div class="mb-2">
      <label class="form-label small mb-1">content</label>
      <textarea class="form-control form-control-sm" rows="2" data-action="change->tabler-ui--docs-editor#applyField"
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["content"])}' data-editor-control="text"
      >${escapeHtml(node.content || "")}</textarea>
    </div>
  `
}

function attrsFields(node, { withSpan }) {
  const attrs = node.attrs || {}
  const attrInputs = attrKeys().map((key) => `
    <div class="mb-2">
      <label class="form-label small mb-1">${key}</label>
      <input type="text" class="form-control form-control-sm" data-action="change->tabler-ui--docs-editor#applyField"
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["attrs", key])}' data-editor-control="text"
             value="${escapeHtml(attrs[key] || "")}">
    </div>
  `).join("")

  return `
    <h4 class="mb-2">${node.kind === "row" ? "Row" : "Column"}</h4>
    ${withSpan ? spanFields(node) : ""}
    ${attrInputs}
  `
}

function spanFields(node) {
  const span = node.span || {}
  const cells = spanKeys().map((key) => {
    const options = spanValues().map((v) => (
      `<option value="${v}" ${String(span[key]) === String(v) ? "selected" : ""}>${v}</option>`
    )).join("")

    return `
      <div class="col-6 mb-2">
        <label class="form-label small mb-1">${key}</label>
        <select class="form-select form-select-sm" data-action="change->tabler-ui--docs-editor#applyField"
                data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["span", key])}' data-editor-control="span">
          <option value="">--</option>
          ${options}
        </select>
      </div>
    `
  }).join("")

  return `<div class="row">${cells}</div>`
}

function partialFields(node) {
  return `
    <h4 class="mb-2">Partial</h4>
    <div class="mb-2">
      <label class="form-label small mb-1">path</label>
      <input type="text" class="form-control form-control-sm" data-action="change->tabler-ui--docs-editor#applyField"
             data-editor-node-id="${node.id}" data-editor-path='${JSON.stringify(["path"])}' data-editor-control="text"
             value="${escapeHtml(node.path || "")}">
    </div>
  `
}

// --- component / builder_item -- schema-driven ------------------------

function componentFields(schema, node) {
  if (!schema) return '<p class="text-secondary small mb-0">Loading component schema...</p>'

  const meta = schema.components && schema.components[node.name]
  if (!meta) return `<p class="text-secondary small mb-0">Unknown component '${escapeHtml(node.name)}'.</p>`

  const args = (meta.args || []).map((a) => (
    optionControlHtml(node, { name: a.name, control: a.control }, ["args"], node.args && node.args[a.name])
  )).join("")
  const options = (meta.options || []).map((o) => optionAware(node, o, node.options && node.options[o.name])).join("")
  const builderButtons = meta.builder && meta.builder.root ? builderAddButtons(node, meta.builder.root, "root") : ""

  return `
    <h4 class="mb-1">${escapeHtml(meta.title)}</h4>
    ${meta.description ? `<p class="text-secondary small">${escapeHtml(meta.description)}</p>` : ""}
    ${args}
    ${options}
    ${builderButtons}
    ${htmlPartsHtml(node, meta.htmlParts)}
    ${unsupportedHtml(meta.unsupported)}
  `
}

function builderItemFields(schema, node, context) {
  if (!schema) return '<p class="text-secondary small mb-0">Loading component schema...</p>'
  if (!context) return '<p class="text-secondary small mb-0">Could not determine this item\'s owning component.</p>'

  const component = schema.components && schema.components[context.componentName]
  const levelDef = component && component.builder && component.builder[context.level]
  const methodDef = levelDef && levelDef[node.method]
  if (!methodDef) return `<p class="text-secondary small mb-0">Unknown builder method '${escapeHtml(node.method)}'.</p>`

  const argHtml = methodDef.arg
    ? optionControlHtml(node, { name: methodDef.arg.name, control: methodDef.arg.control }, ["args"],
                         node.args && node.args[methodDef.arg.name])
    : ""
  const options = (methodDef.options || []).map((o) => optionAware(node, o, node.options && node.options[o.name])).join("")
  const nestedButtons = (methodDef.nests && component.builder[methodDef.nests])
    ? builderAddButtons(node, component.builder[methodDef.nests], methodDef.nests)
    : ""

  return `
    <h4 class="mb-2">${escapeHtml(context.componentName)}#${escapeHtml(node.method)}</h4>
    ${argHtml}
    ${options}
    ${nestedButtons}
    ${htmlPartsHtml(node, methodDef.htmlParts)}
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

function optionAware(node, option, currentValue) {
  if (option.control === "columns") return columnsControlHtml(node, option, currentValue)
  if (option.control === "rows") return rowsControlHtml(node, option, currentValue)
  return optionControlHtml(node, option, ["options"], currentValue)
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
function optionControlHtml(node, option, pathPrefix, currentValue) {
  const path = JSON.stringify([...pathPrefix, option.name])
  const value = currentValue === undefined ? "" : currentValue
  const common = `data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="${option.control}"`

  switch (option.control) {
    case "checkbox":
      return `
        <div class="mb-2 form-check">
          <input type="checkbox" class="form-check-input" id="opt-${node.id}-${escapeHtml(option.name)}" ${common}
                 data-action="change->tabler-ui--docs-editor#applyField" ${value === true ? "checked" : ""}>
          <label class="form-check-label" for="opt-${node.id}-${escapeHtml(option.name)}">${escapeHtml(option.name)}</label>
          ${option.description ? `<div class="text-secondary small">${escapeHtml(option.description)}</div>` : ""}
        </div>
      `
    case "number":
      return fieldWrap(option, `
        <input type="number" class="form-control form-control-sm" ${common}
               data-action="change->tabler-ui--docs-editor#applyField" value="${value === "" ? "" : escapeHtml(value)}">
      `)
    case "select":
      return fieldWrap(option, selectControlHtml(option, common, value))
    case "json":
      return fieldWrap(option, `
        <textarea class="form-control form-control-sm" rows="3" ${common}
                  data-action="change->tabler-ui--docs-editor#applyField"
        >${value === "" ? "" : escapeHtml(JSON.stringify(value, null, 2))}</textarea>
      `)
    case "text":
    default:
      return fieldWrap(option, `
        <input type="text" class="form-control form-control-sm" ${common}
               data-action="change->tabler-ui--docs-editor#applyField" value="${escapeHtml(value)}">
      `)
  }
}

function selectControlHtml(option, common, value) {
  const options = (option.values || []).map((v) => (
    `<option value="${escapeHtml(v)}" ${String(value) === String(v) ? "selected" : ""}>${escapeHtml(v)}</option>`
  )).join("")

  return `
    <select class="form-select form-select-sm" ${common} data-action="change->tabler-ui--docs-editor#applyField">
      <option value="">(default)</option>
      ${options}
    </select>
  `
}

function rowsControlHtml(node, option, currentValue) {
  const value = currentValue === undefined ? [] : currentValue
  const path = JSON.stringify(["options", option.name])

  return fieldWrap(option, `
    <textarea class="form-control form-control-sm" rows="4"
              data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="json"
              data-action="change->tabler-ui--docs-editor#applyField"
    >${escapeHtml(JSON.stringify(value, null, 2))}</textarea>
    <div class="text-secondary small">Each row's keys should match a column's key.</div>
  `)
}

function columnsControlHtml(node, option, currentValue) {
  const columns = Array.isArray(currentValue) ? currentValue : []
  const fields = option.fields || []
  const rows = columns.map((col, index) => columnRowHtml(node, option.name, fields, col, index)).join("")

  return `
    <div class="mb-3">
      <label class="form-label small mb-1">${escapeHtml(option.name)}</label>
      <div>${rows}</div>
      <button type="button" class="btn btn-sm btn-outline-secondary mt-1"
              data-action="click->tabler-ui--docs-editor#addColumn"
              data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(option.name)}">
        Add column
      </button>
    </div>
  `
}

function columnRowHtml(node, optionName, fields, col, index) {
  const inputs = fields.map((f) => {
    const value = col && col[f.name] != null ? col[f.name] : ""
    return `
      <input type="text" class="form-control form-control-sm mb-1"
             placeholder="${escapeHtml(f.name)}${f.required ? " *" : ""}" value="${escapeHtml(value)}"
             data-action="change->tabler-ui--docs-editor#updateColumnField"
             data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}"
             data-editor-index="${index}" data-editor-field="${escapeHtml(f.name)}">
    `
  }).join("")

  return `
    <div class="border rounded p-2 mb-2">
      ${inputs}
      <button type="button" class="btn btn-sm btn-outline-danger"
              data-action="click->tabler-ui--docs-editor#removeColumn"
              data-editor-node-id="${node.id}" data-editor-option="${escapeHtml(optionName)}" data-editor-index="${index}">
        Remove
      </button>
    </div>
  `
}

function htmlPartsHtml(node, parts) {
  if (!parts || parts.length === 0) return ""

  const rows = parts.map((part) => {
    const value = (node.html && node.html[part]) || {}
    const path = JSON.stringify(["html", part])
    return `
      <div class="mb-2">
        <label class="form-label small mb-1">html: ${escapeHtml(part)}</label>
        <textarea class="form-control form-control-sm" rows="2"
                  data-editor-node-id="${node.id}" data-editor-path='${path}' data-editor-control="json"
                  data-action="change->tabler-ui--docs-editor#applyField"
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
