// Client side of the in-browser design editor
// (docs/app/views/tabler_ui/docs/editor/show.html.erb). Owns four things:
//
//   1. A localStorage-backed workspace (multi-file document) -- see
//      editor/workspace.js for the storage discipline.
//   2. Three read-only-from-outside panels rebuilt from that workspace and
//      the /ui/editor/schema payload: Explorer, Components palette, and
//      the Structure/Inspector panes.
//   3. A debounced POST to previewUrlValue that renders the current file
//      into the sandboxed <iframe data-tabler-ui--docs-editor-target="frame">
//      and shows the generated .html.erb in the Code pane.
//   4. Click-to-select and dblclick-to-edit inside that iframe.
//
// ## The one rule everything else here is built around
//
// NEVER re-render an element being typed into, and never re-render an
// ancestor of it. This bit the table component's own filter toolbar once
// (see docs/app/javascript/controllers/tabler_ui/docs/search_controller.js's
// header, "lesson 3") and it bites twice as hard here: the in-canvas
// contenteditable field IS the source of truth for its own text while it's
// focused, and replacing its innerHTML mid-edit doesn't just lose focus,
// it destroys the caret. So:
//
//   - Every property-panel control fires on "change", not "input" -- see
//     editor/inspector.js's own header for why that alone defuses the
//     hazard for every field EXCEPT the canvas.
//   - The canvas contenteditable field is the one place "input" fires
//     per-keystroke. On it: update the tree + code pane + storage
//     synchronously, but suppress the canvas repaint (`_canvasEditing` is
//     truthy) until blur. See #_onFrameInput / #_endCanvasEdit.
//   - The Structure tab's label for the node being canvas-edited is
//     patched with a targeted textContent write (#_syncStructureLabel),
//     never a full rebuild -- the panel isn't itself being typed into, but
//     rebuilding its innerHTML on every keystroke would still be wasteful
//     and is exactly the kind of "rebuild in response to input" habit this
//     file avoids everywhere.
//
// ## Two-target theme mirror
//
// dark_mode_controller.js writes `data-bs-theme` on BOTH
// document.documentElement and document.body, and fires no event of its
// own -- this controller mirrors it into the sandboxed preview frame (a
// separate `document`, so it never sees that write on its own) via a
// MutationObserver on documentElement, torn down in disconnect(). Reading
// `document.documentElement` and the frame's `contentDocument` are the
// ONLY two document-level reads in this file (rule 6, CLAUDE.md) --
// everything else stays inside this.element or the frame's own document.
//
// ## Autosave has nothing to flush
//
// Every tree/workspace mutation in this file (#_updateTree, the CRUD
// helpers) calls editor/workspace.js#saveWorkspace synchronously, in the
// same tick -- never inside the debounced preview timer. So the only thing
// #disconnect's clearTimeout ever cancels is a not-yet-sent PREVIEW
// request; the workspace itself is never behind what's in localStorage,
// and a Turbo navigation can never drop an edit that already happened.
import { Controller } from "@hotwired/stimulus"
import * as Workspace from "controllers/tabler_ui/docs/editor/workspace"
import * as Tree from "controllers/tabler_ui/docs/editor/tree"
import { fetchSchema } from "controllers/tabler_ui/docs/editor/schema"
import { explorerHtml } from "controllers/tabler_ui/docs/editor/explorer"
import { paletteHtml } from "controllers/tabler_ui/docs/editor/palette"
import { inspectorHtml } from "controllers/tabler_ui/docs/editor/inspector"
import { structureHtml } from "controllers/tabler_ui/docs/editor/structure"
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"

const FIELD_PRIORITY = ["title", "text", "label", "value"]

export default class extends Controller {
  static targets = ["explorer", "palette", "structure", "code", "inspector", "frame", "errors", "filename"]
  static values = {
    schemaUrl: { type: String, default: "" },
    previewUrl: { type: String, default: "" },
    csrfToken: { type: String, default: "" },
    debounce: { type: Number, default: 250 }
  }

  connect() {
    const loaded = Workspace.loadWorkspace()
    this._workspace = loaded.workspace
    this._schema = null
    this._selectedNodeId = null
    this._selectedSlotTarget = null
    this._canvasEditing = null
    this._frameSelectedEl = null
    this._previewRequestId = 0
    this._lastHtml = null
    this._lastErb = ""

    if (loaded.error) this._renderErrors([loaded.error])

    this._renderToolbarFilename()
    this._renderExplorer()
    this._renderStructure()
    this._renderInspector()

    fetchSchema(this.schemaUrlValue)
      .then((schema) => {
        this._schema = schema
        this._renderPalette()
        this._renderInspector()
        this._renderStructure()
      })
      .catch((error) => this._renderErrors([`could not load the component schema: ${error.message}`]))

    // See this file's header, "Two-target theme mirror" -- the only other
    // document-level read is the frame's own contentDocument, in
    // #_onFrameLoad below.
    this._themeObserver = new MutationObserver(() => this._syncFrameTheme())
    this._themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-bs-theme"] })

    if (this.hasFrameTarget) {
      this._frameLoadHandler = () => this._onFrameLoad()
      this.frameTarget.addEventListener("load", this._frameLoadHandler)
    }

    this._schedulePreview(true)
  }

  disconnect() {
    if (this._previewTimeout) clearTimeout(this._previewTimeout)
    if (this._previewAbort) this._previewAbort.abort()
    if (this._themeObserver) this._themeObserver.disconnect()
    if (this.hasFrameTarget && this._frameLoadHandler) {
      this.frameTarget.removeEventListener("load", this._frameLoadHandler)
    }
    this._detachFrameListeners()
  }

  // === Explorer =============================================================

  selectFile(event) {
    const path = event.currentTarget.dataset.editorPath
    this._workspace = Workspace.setOpen(this._workspace, path)
    this._selectedNodeId = null
    this._selectedSlotTarget = null
    this._afterStructuralChange()
  }

  newFile() {
    // eslint-disable-next-line no-alert
    const name = window.prompt("New file path (e.g. users/index.html.erb):", "untitled.html.erb")
    if (!name) return
    this._workspace = Workspace.createFile(this._workspace, name)
    this._selectedNodeId = null
    this._selectedSlotTarget = null
    this._afterStructuralChange()
  }

  newFolder() {
    // eslint-disable-next-line no-alert
    const name = window.prompt("New folder path (e.g. users):")
    if (!name) return
    this._workspace = Workspace.createDirectory(this._workspace, name)
    this._afterStructuralChange({ skipPreview: true })
  }

  renameFile(event) {
    event.stopPropagation()
    const path = event.currentTarget.dataset.editorPath
    // eslint-disable-next-line no-alert
    const name = window.prompt("Rename to:", path)
    if (!name || name === path) return
    this._workspace = Workspace.renameFile(this._workspace, path, name)
    this._afterStructuralChange()
  }

  duplicateFile(event) {
    event.stopPropagation()
    const path = event.currentTarget.dataset.editorPath
    this._workspace = Workspace.duplicateFile(this._workspace, path)
    this._afterStructuralChange()
  }

  deleteFile(event) {
    event.stopPropagation()
    const path = event.currentTarget.dataset.editorPath
    // eslint-disable-next-line no-alert
    if (!window.confirm(`Delete ${path}?`)) return
    this._workspace = Workspace.deleteFile(this._workspace, path)
    // The selected node (if any) belonged to whichever file was open before
    // this delete -- if that file just changed (this delete removed the
    // open file, or a different one), the old node id no longer means
    // anything in the new open file's tree.
    this._selectedNodeId = null
    this._selectedSlotTarget = null
    this._afterStructuralChange()
  }

  // === Palette / structural editing ========================================

  addFromPalette(event) {
    const el = event.currentTarget
    const node = this._buildNewNode(el.dataset.editorKind, el.dataset.editorComponent)
    if (!node) return

    this._updateTree((tree) => this._insertIntoSelection(tree, node))
    this._schedulePreview()
  }

  addBuilderItem(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const method = el.dataset.editorMethod
    const item = { kind: "builder_item", id: Tree.generateId(), method, args: {}, options: {} }

    this._updateTree((tree) => Tree.insertNode(tree, nodeId, item, { container: "items" }))
    this._renderInspector()
    this._schedulePreview()
  }

  selectStructureNode(event) {
    this._selectedSlotTarget = null
    this._selectNode(event.currentTarget.dataset.editorNodeId)
  }

  selectSlot(event) {
    const el = event.currentTarget
    this._selectedNodeId = null
    this._selectedSlotTarget = { nodeId: el.dataset.editorNodeId, slotName: el.dataset.editorSlot }
    this._renderStructure()
    this._renderInspector()
    this._highlightCanvasSelection(null)
  }

  moveNodeUp(event) {
    event.stopPropagation()
    this._updateTree((tree) => Tree.moveNode(tree, event.currentTarget.dataset.editorNodeId, "up"))
    this._schedulePreview()
  }

  moveNodeDown(event) {
    event.stopPropagation()
    this._updateTree((tree) => Tree.moveNode(tree, event.currentTarget.dataset.editorNodeId, "down"))
    this._schedulePreview()
  }

  deleteNode(event) {
    event.stopPropagation()
    const nodeId = event.currentTarget.dataset.editorNodeId
    // eslint-disable-next-line no-alert
    if (!window.confirm("Delete this node?")) return

    this._updateTree((tree) => Tree.removeNode(tree, nodeId))
    if (this._selectedNodeId === nodeId) this._selectNode(null)
    this._schedulePreview()
  }

  // === Property panel =======================================================

  applyField(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const path = JSON.parse(el.dataset.editorPath)
    const value = this._coerceControlValue(el)
    if (value === undefined && el.value !== "" && el.dataset.editorControl === "json") return // parse error, already reported

    this._updateTree((tree) => Tree.setNodeValue(tree, nodeId, path, value))
    this._schedulePreview()
  }

  addColumn(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const columns = Array.isArray(current) ? current.slice() : []
      columns.push({ key: "" })
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
    })
    this._renderInspector()
    this._schedulePreview()
  }

  removeColumn(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption
    const index = Number(el.dataset.editorIndex)

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const columns = Array.isArray(current) ? current.slice() : []
      columns.splice(index, 1)
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
    })
    this._renderInspector()
    this._schedulePreview()
  }

  updateColumnField(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption
    const index = Number(el.dataset.editorIndex)
    const field = el.dataset.editorField

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const columns = Array.isArray(current) ? current.map((c) => ({ ...c })) : []
      if (!columns[index]) columns[index] = {}
      if (el.value === "") {
        delete columns[index][field]
      } else {
        columns[index][field] = el.value
      }
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
    })
    this._schedulePreview()
  }

  // === Copy / Download / Export =============================================

  copyErb() {
    this._copyText(this._lastErb || "")
  }

  download() {
    const path = this._workspace.open || "design.html.erb"
    this._downloadText(this._lastErb || "", path.split("/").pop())
  }

  exportAll() {
    const paths = Object.keys(this._workspace.files)
    const results = []

    const runNext = (i) => {
      if (i >= paths.length) {
        const bundle = results.map((r) => `<%# ${r.path} %>\n${r.erb}\n`).join("\n\n")
        this._downloadText(bundle, "workspace-export.html.erb")
        return
      }

      const path = paths[i]
      this._fetchPreview(path)
        .then((data) => results.push({ path, erb: data.erb || `<%# ${(data.errors || []).join(", ")} %>` }))
        .catch((error) => results.push({ path, erb: `<%# request failed: ${error.message} %>` }))
        .then(() => runNext(i + 1))
    }
    runNext(0)
  }

  _copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(() => this._legacyCopy(text))
    } else {
      this._legacyCopy(text)
    }
  }

  _legacyCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    this.element.appendChild(textarea)
    textarea.focus()
    textarea.select()
    try {
      document.execCommand("copy")
    } catch (e) {
      this._renderErrors([`could not copy to clipboard: ${e.message}`])
    }
    this.element.removeChild(textarea)
  }

  _downloadText(text, filename) {
    const blob = new Blob([text], { type: "text/plain" })
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = filename
    this.element.appendChild(link)
    link.click()
    this.element.removeChild(link)
    URL.revokeObjectURL(url)
  }

  // === Preview ================================================================

  _schedulePreview(immediate = false) {
    if (this._previewTimeout) clearTimeout(this._previewTimeout)
    if (immediate) {
      this._sendPreview()
    } else {
      this._previewTimeout = setTimeout(() => this._sendPreview(), this.debounceValue)
    }
  }

  // A monotonic request id plus an AbortController per request -- so a
  // slow response can never overwrite a newer render. #_fetchPreview
  // itself is the plain, uncoordinated request primitive; only the LIVE
  // preview flow (this method) applies the abort-the-previous-one /
  // ignore-if-superseded logic. #exportAll deliberately calls
  // #_fetchPreview directly, one file after another, so it is never
  // aborted by (and never aborts) whatever the live preview is doing.
  _sendPreview() {
    const path = this._workspace.open
    if (!path) return

    if (this._previewAbort) this._previewAbort.abort()
    const controller = new AbortController()
    this._previewAbort = controller
    const requestId = (this._previewRequestId += 1)

    this._fetchPreview(path, controller.signal)
      .then((data) => {
        if (requestId !== this._previewRequestId) return // superseded by a newer request
        this._handlePreviewResult(data)
      })
      .catch((error) => {
        if (error.name === "AbortError") return
        if (requestId !== this._previewRequestId) return
        this._renderErrors([`preview request failed: ${error.message}`])
      })
  }

  // @return Promise<Object> the parsed response body -- shaped
  //   { html, erb, workspace, errors } on success or { errors } on a 422,
  //   Editor Controller#preview is always-JSON on every path (see that
  //   controller's own doc), so the body alone tells the two apart.
  _fetchPreview(path, signal) {
    return fetch(this.previewUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfTokenValue
      },
      body: JSON.stringify({ path, workspace: this._workspace }),
      signal
    }).then((response) => response.json())
  }

  _handlePreviewResult(data) {
    this._renderErrors(data.errors || [])
    if (data.workspace) {
      this._workspace = data.workspace
      this._persist()
    }
    if (typeof data.erb === "string") this._renderCode(data.erb)
    if (typeof data.html === "string") this._renderCanvas(data.html)
  }

  // === Canvas (sandboxed preview iframe) ====================================

  _onFrameLoad() {
    // Same-origin sandboxed preview frame served by EditorController#frame
    // -- see this file's header for why this and document.documentElement
    // are the only two document-level reads in this controller.
    const doc = this.frameTarget.contentDocument
    if (!doc) return

    this._detachFrameListeners()
    this._frameDoc = doc
    this._syncFrameTheme()

    this._frameClickHandler = (event) => this._onFrameClick(event)
    this._frameDblClickHandler = (event) => this._onFrameDblClick(event)
    this._frameInputHandler = (event) => this._onFrameInput(event)
    this._frameBlurHandler = (event) => this._onFrameBlur(event)
    this._framePasteHandler = (event) => this._onFramePaste(event)

    doc.addEventListener("click", this._frameClickHandler, true)
    doc.addEventListener("dblclick", this._frameDblClickHandler)
    doc.addEventListener("input", this._frameInputHandler, true)
    doc.addEventListener("blur", this._frameBlurHandler, true)
    doc.addEventListener("paste", this._framePasteHandler, true)

    this._paintCanvas()
  }

  _detachFrameListeners() {
    if (!this._frameDoc) return
    this._frameDoc.removeEventListener("click", this._frameClickHandler, true)
    this._frameDoc.removeEventListener("dblclick", this._frameDblClickHandler)
    this._frameDoc.removeEventListener("input", this._frameInputHandler, true)
    this._frameDoc.removeEventListener("blur", this._frameBlurHandler, true)
    this._frameDoc.removeEventListener("paste", this._framePasteHandler, true)
    this._frameDoc = null
  }

  _syncFrameTheme() {
    if (!this._frameDoc) return
    const theme = document.documentElement.getAttribute("data-bs-theme") || "light"
    this._frameDoc.documentElement.setAttribute("data-bs-theme", theme)
    if (this._frameDoc.body) this._frameDoc.body.setAttribute("data-bs-theme", theme)
  }

  _renderCanvas(html) {
    this._lastHtml = html
    this._paintCanvas()
  }

  _paintCanvas() {
    // Rule 3 (this file's header): never repaint the canvas while a field
    // inside it is being typed into -- the DOM already shows the truth,
    // and replacing innerHTML would destroy the caret.
    if (this._canvasEditing || !this._frameDoc || this._lastHtml == null) return
    const canvasEl = this._frameDoc.getElementById("tabler-ui-editor-canvas")
    if (canvasEl) canvasEl.innerHTML = this._lastHtml
    this._highlightCanvasSelection(this._selectedNodeId)
  }

  _onFrameClick(event) {
    // Never let a link (or an auto-submitting form) inside the previewed
    // design navigate the sandboxed frame away from the editor.
    event.preventDefault()
    const target = event.target.closest ? event.target.closest("[data-editor-node-id]") : null

    // A click anywhere other than the element currently being edited ends
    // that edit properly (repaint re-armed, contenteditable removed) --
    // relying on the browser's own blur to always fire here would be
    // fragile (whether clicking a non-focusable element blurs the
    // previously focused one is not guaranteed the same way everywhere).
    if (this._canvasEditing && target !== this._canvasEditing.element) this._endCanvasEdit()

    if (!target) return
    this._selectedSlotTarget = null
    this._selectNode(target.getAttribute("data-editor-node-id"))
  }

  _onFrameDblClick(event) {
    const target = event.target.closest ? event.target.closest("[data-editor-node-id]") : null
    if (!target) return
    event.preventDefault()
    this._beginCanvasEdit(target)
  }

  _onFrameInput(event) {
    if (!this._canvasEditing || event.target !== this._canvasEditing.element) return
    this._onCanvasInput()
  }

  _onFrameBlur(event) {
    if (!this._canvasEditing || event.target !== this._canvasEditing.element) return
    this._endCanvasEdit()
  }

  _onFramePaste(event) {
    if (!this._canvasEditing || event.target !== this._canvasEditing.element) return
    event.preventDefault()

    const view = this._frameDoc.defaultView
    const text = (event.clipboardData || view.clipboardData).getData("text/plain")
    const selection = view.getSelection()
    if (!selection.rangeCount) return

    selection.deleteFromDocument()
    selection.getRangeAt(0).insertNode(this._frameDoc.createTextNode(text))
    selection.collapseToEnd()
    this._onCanvasInput()
  }

  _beginCanvasEdit(el) {
    const nodeId = el.getAttribute("data-editor-node-id")
    const tree = this._currentTree()
    const node = tree && Tree.findNode(tree, nodeId)
    if (!node) return

    const explicitField = el.getAttribute("data-editor-field")
    const path = explicitField ? [explicitField] : this._resolveEditableField(node, el.textContent)

    this._selectedSlotTarget = null
    this._selectNode(nodeId)
    if (!path) return // no matching field -- selection alone still opens the inspector

    el.contentEditable = "plaintext-only"
    if (el.contentEditable !== "plaintext-only") el.contentEditable = "true"
    el.focus()

    this._canvasEditing = { nodeId, path, element: el }
  }

  // "options" only (not "args") -- see editor_controller's task brief: an
  // in-canvas edit resolves to a node's *option*, never its required
  // positional.
  _resolveEditableField(node, text) {
    const needle = (text || "").trim()
    if (needle === "" || !node.options) return null

    const matches = Object.keys(node.options).filter((key) => (
      typeof node.options[key] === "string" && node.options[key].trim() === needle
    ))
    if (matches.length === 0) return null

    matches.sort((a, b) => this._fieldPriority(a) - this._fieldPriority(b))
    return ["options", matches[0]]
  }

  _fieldPriority(name) {
    const idx = FIELD_PRIORITY.indexOf(name)
    return idx === -1 ? FIELD_PRIORITY.length : idx
  }

  _onCanvasInput() {
    const { nodeId, path, element } = this._canvasEditing
    const value = element.textContent

    // Rule 3: update tree + code pane + storage now, but #_updateTree's
    // rebuildStructure: false means the Structure panel is patched with a
    // targeted write below instead of a full rebuild, and #_paintCanvas
    // (called from #_renderCanvas inside #_handlePreviewResult) is a no-op
    // while this._canvasEditing is set.
    this._updateTree((tree) => Tree.setNodeValue(tree, nodeId, path, value), { rebuildStructure: false })
    this._syncStructureLabel(nodeId)
    this._schedulePreview()
  }

  _endCanvasEdit() {
    const editing = this._canvasEditing
    if (!editing) return

    editing.element.removeAttribute("contenteditable")
    this._canvasEditing = null
    this._renderStructure() // now safe -- catches up on every edit made while typing
    this._schedulePreview(true) // rule 3: the canvas itself repaints on blur, not before
  }

  // === Selection =============================================================

  _selectNode(id) {
    this._selectedNodeId = id
    this._renderInspector()
    this._highlightCanvasSelection(id)
    this._highlightStructureSelection(id)
  }

  _highlightCanvasSelection(id) {
    if (this._frameSelectedEl) this._frameSelectedEl.style.outline = ""
    this._frameSelectedEl = null
    if (!id || !this._frameDoc) return

    const el = this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(id)}"]`)
    if (el) {
      el.style.outline = "2px solid #206bc4"
      this._frameSelectedEl = el
    }
  }

  _highlightStructureSelection(id) {
    if (!this.hasStructureTarget) return
    this.structureTarget.querySelectorAll(".docs-editor-structure-row.active").forEach((el) => el.classList.remove("active"))
    if (!id) return
    const row = this.structureTarget.querySelector(`[data-editor-node-id="${this._cssEscape(id)}"]`)
    if (row) row.classList.add("active")
  }

  _cssEscape(value) {
    return (typeof CSS !== "undefined" && CSS.escape) ? CSS.escape(value) : String(value).replace(/[^a-zA-Z0-9_-]/g, "")
  }

  // === Tree / workspace mutation helpers ====================================

  _currentTree() {
    const path = this._workspace.open
    return (path && this._workspace.files[path]) ? this._workspace.files[path].tree : null
  }

  _updateTree(mutator, { rebuildStructure = true } = {}) {
    const path = this._workspace.open
    if (!path || !this._workspace.files[path]) return

    const newTree = mutator(this._workspace.files[path].tree)
    this._workspace = { ...this._workspace, files: { ...this._workspace.files, [path]: { tree: newTree } } }
    this._persist()
    if (rebuildStructure) this._renderStructure()
  }

  _persist() {
    try {
      Workspace.saveWorkspace(this._workspace)
    } catch (e) {
      this._renderErrors([`could not save to local storage: ${e.message}`])
    }
  }

  _afterStructuralChange(opts = {}) {
    // Switching/renaming/deleting a file changes which tree the canvas
    // shows -- an edit in progress against the OLD file's element must not
    // keep blocking every future repaint (#_paintCanvas no-ops while
    // this._canvasEditing is set).
    if (this._canvasEditing) this._endCanvasEdit()

    this._persist()
    this._renderToolbarFilename()
    this._renderExplorer()
    this._renderStructure()
    this._renderInspector()
    if (!opts.skipPreview) this._schedulePreview(true)
  }

  _insertIntoSelection(tree, node) {
    if (this._selectedSlotTarget) {
      const { nodeId, slotName } = this._selectedSlotTarget
      return Tree.insertNode(tree, nodeId, node, { slot: slotName })
    }

    const selectedId = this._selectedNodeId
    if (!selectedId) return Tree.insertNode(tree, tree.id, node)

    const target = Tree.findNode(tree, selectedId)
    if (!target) return Tree.insertNode(tree, tree.id, node)

    if (["fragment", "row", "column"].includes(target.kind)) {
      return Tree.insertNode(tree, target.id, node)
    }
    return Tree.insertAfter(tree, selectedId, node)
  }

  _buildNewNode(kind, componentName) {
    const id = Tree.generateId()
    switch (kind) {
      case "row": return { kind: "row", id, attrs: {}, children: [] }
      case "column": return { kind: "column", id, span: { base: 12 }, attrs: {}, children: [] }
      case "heading": return { kind: "heading", id, level: 2, content: "New heading" }
      case "text": return { kind: "text", id, tag: "p", content: "New text" }
      case "partial": return { kind: "partial", id, path: "" }
      case "component": return this._buildComponentNode(id, componentName)
      default: return null
    }
  }

  _buildComponentNode(id, componentName) {
    const meta = this._schema && this._schema.components && this._schema.components[componentName]
    const node = { kind: "component", id, name: componentName, args: {}, options: {} }
    if (meta && meta.args) meta.args.forEach((a) => { node.args[a.name] = "" })
    if (meta && meta.builder) {
      node.items = []
    } else {
      node.slots = {}
    }
    return node
  }

  _coerceControlValue(el) {
    const control = el.dataset.editorControl

    if (control === "checkbox") return el.checked
    if (control === "number") return el.value === "" ? undefined : Number(el.value)
    if (control === "span") {
      if (el.value === "") return undefined
      return el.value === "auto" ? "auto" : Number(el.value)
    }
    if (control === "json") {
      if (el.value.trim() === "") return undefined
      try {
        return JSON.parse(el.value)
      } catch (e) {
        this._renderErrors([`invalid JSON: ${e.message}`])
        return undefined
      }
    }
    return el.value === "" ? undefined : el.value
  }

  // === Rendering =============================================================

  _renderToolbarFilename() {
    if (!this.hasFilenameTarget) return
    this.filenameTarget.textContent = this._workspace.open || "(no file open)"
  }

  _renderExplorer() {
    if (!this.hasExplorerTarget) return
    this.explorerTarget.innerHTML = explorerHtml(Workspace.buildIndex(this._workspace))
  }

  _renderPalette() {
    if (!this.hasPaletteTarget || !this._schema) return
    this.paletteTarget.innerHTML = paletteHtml(this._schema)
  }

  _renderStructure() {
    if (!this.hasStructureTarget) return
    this.structureTarget.innerHTML = structureHtml(this._schema, this._currentTree(), this._selectedNodeId, this._selectedSlotTarget)
  }

  _syncStructureLabel(nodeId) {
    if (!this.hasStructureTarget) return
    const tree = this._currentTree()
    const node = tree && Tree.findNode(tree, nodeId)
    // Only heading/text rows show their own edited value in the label
    // (structure.js#labelFor: "Heading: ..."/"Text: ..."). A component's
    // row shows only its component name, which an in-canvas *option* edit
    // never changes -- nothing to sync there, so leave the row alone
    // rather than guessing at a replacement that would be wrong.
    if (!node || (node.kind !== "heading" && node.kind !== "text")) return

    const row = this.structureTarget.querySelector(`[data-editor-node-id="${this._cssEscape(nodeId)}"] .docs-editor-structure-label`)
    if (!row) return

    // Targeted textContent write -- never a rebuild.
    const truncated = (node.content || "").trim().slice(0, 40) || "(empty)"
    row.textContent = `${node.kind === "heading" ? "Heading" : "Text"}: ${truncated}`
  }

  _renderInspector() {
    if (!this.hasInspectorTarget) return
    this.inspectorTarget.innerHTML = inspectorHtml(this._schema, this._currentTree(), this._selectedNodeId, this._selectedSlotTarget)
  }

  _renderCode(erb) {
    this._lastErb = erb
    if (!this.hasCodeTarget) return
    this.codeTarget.innerHTML = `<pre class="docs-editor-code m-0"><code>${escapeHtml(erb)}</code></pre>`
  }

  _renderErrors(list) {
    if (!this.hasErrorsTarget) return
    if (!list || list.length === 0) {
      this.errorsTarget.innerHTML = ""
      return
    }
    const items = list.map((msg) => `<div>${escapeHtml(msg)}</div>`).join("")
    this.errorsTarget.innerHTML = `<div class="alert alert-warning mb-3">${items}</div>`
  }
}
