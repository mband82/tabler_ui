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
//
// ## Native drag-and-drop: the lock and the payload are the same object
//
// Dragging a palette item onto the canvas, or dragging an EXISTING canvas
// node to reorder/reparent it (editor/dnd.js's own header has the full
// mechanism -- two documents, one JS realm, why SortableJS can't do this,
// and which document dragstart/dragend fire in for each of the two) is
// wired through `this._dragState`, set in #paletteDragStart or
// #_onFrameDragStart and read by every dragover/drop/dragend handler
// below. `sourceNodeId` on it is null for a palette drag (there is no
// existing node yet -- #_applyDrop builds a fresh one) and the dragged
// node's id for a canvas-node drag (#_applyDrop instead calls
// Tree.moveNodeTo). It doubles as #_paintCanvas's repaint lock, on top of
// `this._canvasEditing`: a preview response scheduled before the drag
// started can still arrive mid-drag, and replacing the canvas's innerHTML
// while a native drag is in progress over it destroys the dragged element
// and silently aborts the drag in Chrome. `dragend` -- not `drop` -- is
// the only reliable terminator (see dnd.js's header for why dragend,
// uniquely among these events, is guaranteed to fire exactly once no
// matter how the drag ends), so #_endDrag is idempotent and every path
// that can end a drag calls it -- #paletteDragEnd (parent document,
// palette-sourced drags) and #_onFrameDragEnd (frame document, wired in
// #_onFrameLoad/#_detachFrameListeners exactly like every other frame-doc
// listener this controller owns, canvas-node-sourced drags) between them
// cover both documents dragend can ever fire in. Placement math (where a
// drop lands, whether it looks legal, and -- for a component with no
// single obvious landing spot -- which chips to offer) lives in
// editor/drop_target.js, kept pure -- no DOM, no controller state -- so it
// can be reasoned about (and, if it's ever wrong, fixed) without the DOM
// plumbing around it getting in the way.
//
// A canvas node has to be made draggable before any of this can even
// start: #_paintCanvas stamps `draggable="true"` on every freshly-painted
// `[data-editor-node-id]` (and `draggable="false"` on any native
// img/a[href]/[draggable] sitting inside one, so the browser doesn't
// commit to dragging THAT instead -- see that method's own comment). Pure
// presentation, redone on every repaint, never read back into the tree.
import { Controller } from "@hotwired/stimulus"
import * as Workspace from "controllers/tabler_ui/docs/editor/workspace"
import * as Tree from "controllers/tabler_ui/docs/editor/tree"
import { fetchSchema } from "controllers/tabler_ui/docs/editor/schema"
import { explorerHtml } from "controllers/tabler_ui/docs/editor/explorer"
import { paletteHtml } from "controllers/tabler_ui/docs/editor/palette"
import { inspectorHtml } from "controllers/tabler_ui/docs/editor/inspector"
import { structureHtml, labelFor } from "controllers/tabler_ui/docs/editor/structure"
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"
import { exportWorkspaceZip } from "controllers/tabler_ui/docs/editor/export"
import { createOverlay } from "controllers/tabler_ui/docs/editor/overlay"
import * as DnD from "controllers/tabler_ui/docs/editor/dnd"
import { resolveDropTarget, ROOT_GHOST_HEIGHT } from "controllers/tabler_ui/docs/editor/drop_target"

const FIELD_PRIORITY = ["title", "text", "label", "value"]

// A plain object shaped like the DOMRect fields overlay.js's showBox
// actually reads (left/top/width/height, plus right/bottom so its
// off-screen check in #flipAndClamp has real values to compare against
// instead of always seeing `undefined`) -- used by #_paintDragGhost to
// build a ghost-box rect that was never itself measured with
// getBoundingClientRect().
function rectOf(left, top, width, height) {
  return { left, top, width, height, right: left + width, bottom: top + height }
}

// Bound on the undo/redo stacks (#_pushUndoSnapshot et al) -- a safety net
// for an accidental drag/delete, not a full edit-history browser. Small on
// purpose: each entry is a whole workspace object (cheap only because
// nothing here ever mutates a pushed snapshot in place -- see
// #_pushUndoSnapshot's own comment), and a session that has drifted more
// than 20 structural edits past the mistake it wants back is better served
// by fixing it forward than by hunting through a long undo history for it.
const UNDO_STACK_LIMIT = 20

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
    // Set by #_selectFromCanvas when a canvas click/dblclick resolves to a
    // node that lives in a DIFFERENT file (reached through a `partial`
    // node -- see editor/workspace.js#findNodeAcrossWorkspace's own
    // header). Mutually exclusive with _selectedNodeId -- #_selectNode
    // always clears this, and #_selectFromCanvas always clears
    // _selectedNodeId before setting this instead. Shape:
    // {id, path, node, context}.
    this._selectedForeign = null
    this._canvasEditing = null
    this._overlay = null
    // Bounded pre-mutation history for Ctrl/Cmd+Z / Ctrl/Cmd+Shift+Z (see
    // #_updateTree, #_pushUndoSnapshot, #_undo/#_redo, UNDO_STACK_LIMIT
    // above). Each entry is a whole workspace object, pushed by reference
    // -- safe because every mutation in this file (and every CRUD helper
    // in editor/workspace.js) replaces `this._workspace` wholesale rather
    // than mutating it, so a snapshot already on either stack can never be
    // reached back into and changed out from under it.
    this._undoStack = []
    this._redoStack = []
    // The native drag-and-drop payload AND #_paintCanvas's second repaint
    // lock -- see this file's header, "Native drag-and-drop". Set in
    // #paletteDragStart or #_onFrameDragStart, read by every frame-side
    // drag handler, cleared only by #_endDrag.
    this._dragState = null
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

  // Also the target of the "Open <path>" button the read-only inspector
  // shows for a foreign selection (editor/inspector.js#foreignSelectionHtml)
  // -- reused as-is, not duplicated, so there is exactly one place that
  // knows how to switch the open file (see this file's own task note on
  // Workspace.setOpen).
  selectFile(event) {
    const path = event.currentTarget.dataset.editorPath
    this._workspace = Workspace.setOpen(this._workspace, path)
    this._selectedNodeId = null
    this._selectedForeign = null
    this._selectedSlotTarget = null
    this._afterStructuralChange()
  }

  newFile() {
    // eslint-disable-next-line no-alert
    const name = window.prompt("New file path (e.g. users/index.html.erb):", "untitled.html.erb")
    if (!name) return
    this._workspace = Workspace.createFile(this._workspace, name)
    this._selectedNodeId = null
    this._selectedForeign = null
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
    this._selectedForeign = null
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

  // Stimulus action for `dragstart` on a palette item (editor/palette.js
  // and editor/show.html.erb's no-JS fallback both wire this alongside the
  // existing click action -- dragging is additive, never a replacement).
  // Refuses to start a drag while a canvas text edit is in progress --
  // finish that first -- by calling preventDefault() on the dragstart
  // itself, which cancels the native drag before it ever begins; nothing
  // else in this method runs in that case, and this._dragState is never
  // set.
  paletteDragStart(event) {
    if (this._canvasEditing) {
      event.preventDefault()
      return
    }

    const el = event.currentTarget
    const kind = el.dataset.editorKind
    const component = el.dataset.editorComponent || null
    const label = el.textContent.trim()

    // sourceNodeId: null marks this as a "build a fresh node" drag, not a
    // "move an existing one" drag -- see #_onFrameDragStart for the other
    // case and #_applyDrop for where the two paths actually diverge.
    this._dragState = { kind, component, label, target: null, sourceNodeId: null }

    // Firefox refuses to start a drag at all without real data on the
    // dataTransfer -- its value is never read back (see dnd.js's header
    // for why: the payload lives in this._dragState instead, readable
    // from both documents in the same JS realm).
    event.dataTransfer.effectAllowed = "copy"
    event.dataTransfer.setData("text/plain", label)
    DnD.paintDragImage(event, label)

    // Hide the selection box/toolbar for the duration of the drag --
    // #_endDrag's tail (via #_paintCanvas) restores them once the lock
    // lifts. this._selectedNodeId itself is untouched, so the selection
    // that was live before the drag started is still live after it ends.
    if (this._overlay) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
    }
  }

  // `dragend` is the SOURCE-side event (dnd.js's header explains why, in
  // detail) -- it fires on the palette item itself, exactly once per drag
  // no matter how it ended, which is why this is the one place drag
  // cleanup is guaranteed to run even when `drop` never fires at all
  // (Escape, releasing outside the browser window). #_endDrag is
  // idempotent, so this is a no-op on top of a drop that already cleaned
  // up via #_onFrameDrop.
  paletteDragEnd() {
    this._endDrag()
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
    this._selectedForeign = null
    this._selectedSlotTarget = { nodeId: el.dataset.editorNodeId, slotName: el.dataset.editorSlot }
    this._renderStructure()
    this._renderInspector()
    this._highlightCanvasSelection(null)
  }

  moveNodeUp(event) {
    event.stopPropagation()
    this._moveNode(event.currentTarget.dataset.editorNodeId, "up")
  }

  moveNodeDown(event) {
    event.stopPropagation()
    this._moveNode(event.currentTarget.dataset.editorNodeId, "down")
  }

  deleteNode(event) {
    event.stopPropagation()
    this._deleteNode(event.currentTarget.dataset.editorNodeId)
  }

  // Shared bodies for moveNodeUp/moveNodeDown/deleteNode above -- pulled
  // out so the canvas toolbar (#_toolbarButtons) and the keyboard
  // shortcuts (#_onFrameKeydown) can drive the exact same mutation the
  // Structure panel's own row buttons do, without either of them having to
  // fabricate a fake DOM event just to satisfy `event.currentTarget.
  // dataset.editorNodeId`. The Stimulus action methods above stay the
  // public entry points data-action="..." markup binds to; these are the
  // logic every caller (markup, toolbar, keyboard) funnels through.
  _moveNode(nodeId, direction) {
    this._updateTree((tree) => Tree.moveNode(tree, nodeId, direction))
    this._schedulePreview()
  }

  _deleteNode(nodeId) {
    // eslint-disable-next-line no-alert
    if (!window.confirm("Delete this node?")) return

    this._updateTree((tree) => Tree.removeNode(tree, nodeId))
    if (this._selectedNodeId === nodeId) this._selectNode(null)
    this._schedulePreview()
  }

  // Selects the node that owns the container (children/slots/items)
  // holding the current selection -- the canvas toolbar's "Parent" button
  // and the "p" keyboard shortcut both call this directly. Tree.findParent
  // returns the root fragment itself when the selection is one of its
  // direct children; the fragment renders no element of its own (see
  // Tree.findParent's header: "nothing owns the root"), so climbing any
  // further would ask the overlay to highlight something that isn't in the
  // DOM at all. Selecting nothing is the correct end state there, not an
  // error -- the same way #_selectNode(null) already means "nothing
  // selected" everywhere else in this file.
  _selectParentOfSelection() {
    if (!this._selectedNodeId) return
    const tree = this._currentTree()
    if (!tree) return

    const parent = Tree.findParent(tree, this._selectedNodeId)
    this._selectedSlotTarget = null
    this._selectNode(parent && parent.id !== tree.id ? parent.id : null)
  }

  // Deep-copies the selected node (Tree.duplicateNode rekeys the copy and
  // every descendant with a fresh id, so it can never collide with the
  // original) and selects the new copy -- the canvas toolbar's "Duplicate"
  // button and the Ctrl/Cmd+D shortcut both call this directly.
  _duplicateNode(nodeId) {
    if (!nodeId) return
    let newId = null
    this._updateTree((tree) => {
      const result = Tree.duplicateNode(tree, nodeId)
      newId = result.id
      return result.tree
    })
    if (newId) this._selectNode(newId)
    this._schedulePreview()
  }

  // === Drag-and-drop (editor_sortable_controller.js) ========================
  //
  // One handler for every "tabler-ui--docs-editor-sortable:move" event --
  // dispatched by every editor_sortable_controller.js instance attached to
  // a Structure or Explorer container (see structure.js/explorer.js, which
  // own the `structure:<nodeId>:<key>` / `explorer:<dirPath>` container-id
  // encoding jointly with the two methods below). Purely additive: the
  // buttons that already perform these same mutations (moveNodeUp/
  // moveNodeDown/deleteNode above, renameFile) are untouched -- this is
  // just a second way to trigger them, and does nothing this controller
  // couldn't already do without SortableJS ever having loaded.

  handleSortableMove(event) {
    const { itemId, fromContainer, toContainer, newIndex } = event.detail || {}
    if (!itemId || !toContainer) return

    if (toContainer.startsWith("structure:")) {
      this._handleStructureMove(itemId, toContainer, newIndex)
    } else if (toContainer.startsWith("explorer:")) {
      this._handleExplorerMove(itemId, fromContainer, toContainer)
    }
  }

  // Reorder/reparent within the design tree, on top of tree.js's
  // moveNodeTo primitive (remove + insert-at-index against one working
  // tree -- see that function's own header for how a same-container move
  // keeps its target index correct with no extra arithmetic here). This
  // method itself only has to enforce the one rule that's a UI concern
  // rather than a tree-structure one: a slot holds at most one node.
  _handleStructureMove(itemId, toContainer, newIndex) {
    const [, parentId, key] = toContainer.split(":")
    if (!parentId || !key) return

    this._updateTree((tree) => {
      if (key.startsWith("slot__")) {
        const slotName = key.slice("slot__".length)
        const parent = Tree.findNode(tree, parentId)
        const occupant = (parent && parent.slots && parent.slots[slotName]) || []
        // A slot holds at most one node. moveNodeTo/insertAt have no such
        // guard (they only ever insert) -- this is the one place that
        // enforces it: refuse the drop (no-op) rather than silently
        // displacing the existing occupant or stacking two nodes in one
        // slot. Excludes `itemId` itself so dragging a slot's own occupant
        // back onto its own slot isn't mistaken for the slot already being
        // occupied by someone else.
        if (occupant.some((n) => n.id !== itemId)) return tree
      }

      // moveNodeTo no-ops (returns the tree unchanged) if `itemId` isn't
      // found, or if `parentId` can't be found once `itemId` has been
      // removed -- which is exactly what happens when a node is dropped
      // into its own subtree: refuse.
      return Tree.moveNodeTo(tree, itemId, parentId, key, newIndex)
    })
    this._schedulePreview()
  }

  // File-tree move. Only a cross-directory drop is meaningful -- a file's
  // position within one directory has no backing order field (files
  // always render alphabetically, editor/explorer.js), so a same-directory
  // drop is a pure no-op: re-render, which naturally shows alphabetical
  // order again, and persist nothing.
  _handleExplorerMove(itemId, fromContainer, toContainer) {
    if (!itemId || fromContainer === toContainer) {
      this._renderExplorer()
      return
    }

    const newDir = toContainer.slice("explorer:".length)
    const dirPath = newDir === "root" ? "" : newDir
    const newPath = dirPath ? `${dirPath}/${Workspace.basename(itemId)}` : Workspace.basename(itemId)

    this._workspace = Workspace.renameFile(this._workspace, itemId, newPath)
    this._afterStructuralChange()
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

  // Delegates the per-file fetch loop and the zip build to editor/export.js
  // (see that file's header for why it stays sequential and never goes
  // through the live preview's AbortController), passing #_fetchPreview
  // itself as the callback so export.js never needs to know about fetch,
  // CSRF, or this._workspace's shape beyond `files`' keys.
  exportAll() {
    exportWorkspaceZip(this._workspace, { fetchPreview: (path) => this._fetchPreview(path) })
      .then((result) => {
        if (result.error) {
          this._renderErrors([`export failed: ${result.error}`])
          return
        }
        if (result.erroredPaths.length > 0) {
          this._renderErrors([`exported with errors in: ${result.erroredPaths.join(", ")}`])
        }
        this._downloadBlob(result.blob, "workspace-export.zip")
      })
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
    this._downloadBlob(new Blob([text], { type: "text/plain" }), filename)
  }

  // #exportAll's counterpart to #_downloadText -- JSZip's #generateAsync
  // already returns a Blob (a zip is binary; there's no "text" to build
  // one from), so this is the same object-URL-download primitive, just not
  // re-wrapping something that's already a Blob.
  _downloadBlob(blob, filename) {
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
    const sentVersion = this._workspaceVersion || 0

    this._fetchPreview(path, controller.signal)
      .then((data) => {
        if (requestId !== this._previewRequestId) return // superseded by a newer request
        this._handlePreviewResult(data, sentVersion)
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

  // `sentVersion` is #_workspaceVersion as it stood when this response's
  // request went out. If it has moved, the user edited while the request was
  // in flight and everything here describes a workspace that no longer
  // exists -- adopting `data.workspace` would silently throw that edit away.
  //
  // The request-id check upstream does NOT cover this: an edit only schedules
  // its preview on a debounce, so for the length of that debounce there is a
  // newer workspace but not yet a newer request, and the in-flight response
  // still looks current. That window really did lose edits -- reproduced live
  // by adding two components ~300ms apart, where the second vanished.
  //
  // Rendering is skipped too, not just the write-back: the html/erb in a
  // stale response describe the old tree, and the edit that superseded it has
  // already scheduled the preview that will repaint correctly.
  _handlePreviewResult(data, sentVersion) {
    if ((this._workspaceVersion || 0) !== sentVersion) return

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

    // The overlay's root lives in this frame document (see overlay.js's own
    // header for why: getBoundingClientRect() and a position: fixed box
    // only line up when both are read/drawn in the same document), so a
    // fresh one is created on every frame load exactly like the click/
    // dblclick/... listeners just below it, and destroyed in
    // #_detachFrameListeners the same way those are removed -- this frame
    // reloads (a Turbo visit re-renders editor/show.html.erb's <iframe>,
    // or the iframe's own src is reassigned) more than once per page view.
    this._overlay = createOverlay(doc)

    this._frameClickHandler = (event) => this._onFrameClick(event)
    this._frameDblClickHandler = (event) => this._onFrameDblClick(event)
    this._frameInputHandler = (event) => this._onFrameInput(event)
    this._frameBlurHandler = (event) => this._onFrameBlur(event)
    this._framePasteHandler = (event) => this._onFramePaste(event)
    this._frameKeydownHandler = (event) => this._onFrameKeydown(event)
    this._framePointerMoveHandler = (event) => this._onFramePointerMove(event)
    this._framePointerOutHandler = (event) => this._onFramePointerOut(event)
    // Trigger 2/3 of #_repositionOverlay (see that method's own header for
    // all four) -- a DOMRect is a one-time snapshot, so anything that can
    // move the design underneath an already-drawn selection box out from
    // under it has to re-measure and re-apply. `true` (capture) on scroll
    // for the same reason click/input/blur/paste above use it: "scroll"
    // does not bubble, so a listener on `doc` only ever sees it via
    // capture, whether the thing that scrolled is the document itself or
    // some scrollable element inside the design.
    this._frameScrollHandler = () => this._repositionOverlay()
    this._frameResizeHandler = () => this._repositionOverlay()
    // Source-side listeners for a canvas-node-originated drag -- see
    // #_onFrameDragStart/#_onFrameDragEnd's own headers, and dnd.js's, for
    // why these two (unlike dragover/dragenter/dragleave/drop just below)
    // are wired directly here rather than through DnD.attachFrameDropTarget:
    // neither has a "preventDefault on every tick" default-action dance to
    // do, which is the only thing that helper actually exists for.
    this._frameDragStartHandler = (event) => this._onFrameDragStart(event)
    this._frameDragEndHandler = () => this._onFrameDragEnd()

    doc.addEventListener("click", this._frameClickHandler, true)
    doc.addEventListener("dblclick", this._frameDblClickHandler)
    doc.addEventListener("input", this._frameInputHandler, true)
    doc.addEventListener("blur", this._frameBlurHandler, true)
    doc.addEventListener("paste", this._framePasteHandler, true)
    doc.addEventListener("keydown", this._frameKeydownHandler, true)
    // Neither pointermove nor pointerout needs capture -- see
    // #_onFramePointerMove/#_onFramePointerOut for why a plain bubble-phase
    // listener directly on `doc` already sees every one of these (the
    // toolbar's own buttons are the only other thing in the frame that
    // could intercept a pointer event, and elementFromPoint inside the
    // handler is what resolves what's actually under the cursor -- the
    // listener itself never needs to "win a race" against a handler on
    // some element deeper in the design the way click/input/blur/paste do).
    doc.addEventListener("pointermove", this._framePointerMoveHandler)
    doc.addEventListener("pointerout", this._framePointerOutHandler)
    doc.addEventListener("scroll", this._frameScrollHandler, true)
    // Resizing the <iframe> element itself genuinely resizes this guest
    // window (unlike a display:none tab-pane collapsing it -- see trigger 4
    // in #_repositionOverlay), so `resize` on the frame's own `window`
    // fires for that case.
    if (doc.defaultView) doc.defaultView.addEventListener("resize", this._frameResizeHandler)

    doc.addEventListener("dragstart", this._frameDragStartHandler)
    doc.addEventListener("dragend", this._frameDragEndHandler)

    // Target-side drag listeners (dragover/dragenter/dragleave/drop) --
    // both palette-sourced and canvas-node-sourced drags land here
    // identically once they're over the frame; see dnd.js's own header for
    // why THESE four specifically go through DnD.attachFrameDropTarget
    // (the "preventDefault on every tick" dance) while dragstart/dragend
    // just above don't. Paired with the detach call in
    // #_detachFrameListeners just like every other listener this method
    // adds.
    this._dragDropDetach = DnD.attachFrameDropTarget(doc, {
      onDragOver: (event) => this._onFrameDragOver(event),
      onDrop: (event) => this._onFrameDrop(event),
      onLeave: () => this._onFrameDragLeave()
    })

    this._paintCanvas()
  }

  _detachFrameListeners() {
    if (!this._frameDoc) return
    // A frame reload mid-drag (a fresh #_onFrameLoad call replaces the
    // whole frame document out from under it) leaves nothing left to drag
    // onto -- clear the lock so #_paintCanvas isn't wedged forever. The
    // in-flight native drag itself is already dead the instant its target
    // document goes away; there is no drop or dragend left to wait for.
    if (this._dragState) this._dragState = null
    if (this._dragDropDetach) {
      this._dragDropDetach()
      this._dragDropDetach = null
    }
    this._frameDoc.removeEventListener("click", this._frameClickHandler, true)
    this._frameDoc.removeEventListener("dblclick", this._frameDblClickHandler)
    this._frameDoc.removeEventListener("input", this._frameInputHandler, true)
    this._frameDoc.removeEventListener("blur", this._frameBlurHandler, true)
    this._frameDoc.removeEventListener("paste", this._framePasteHandler, true)
    this._frameDoc.removeEventListener("keydown", this._frameKeydownHandler, true)
    this._frameDoc.removeEventListener("pointermove", this._framePointerMoveHandler)
    this._frameDoc.removeEventListener("pointerout", this._framePointerOutHandler)
    this._frameDoc.removeEventListener("scroll", this._frameScrollHandler, true)
    if (this._frameDoc.defaultView) this._frameDoc.defaultView.removeEventListener("resize", this._frameResizeHandler)
    this._frameDoc.removeEventListener("dragstart", this._frameDragStartHandler)
    this._frameDoc.removeEventListener("dragend", this._frameDragEndHandler)
    this._cancelHoverFrame()
    if (this._overlay) {
      this._overlay.destroy()
      this._overlay = null
    }
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
    // and replacing innerHTML would destroy the caret. this._dragState is
    // the second lock, for the same reason: replacing innerHTML under a
    // live native drag destroys the dragged element and silently aborts
    // the drag in Chrome (see this file's header, "Native drag-and-drop").
    if (this._canvasEditing || this._dragState || !this._frameDoc || this._lastHtml == null) return
    const canvasEl = this._frameDoc.getElementById("tabler-ui-editor-canvas")
    if (canvasEl) {
      canvasEl.innerHTML = this._lastHtml
      this._makeCanvasDraggable(canvasEl)
    }
    // The repaint just above replaced the whole canvas subtree, so any
    // element a hover box was pointing at is gone -- clear it rather than
    // leave a box drawn over whatever now occupies that same screen
    // position. The next pointermove re-resolves and redraws it correctly;
    // nothing here needs to re-derive it eagerly the way the selection
    // (below) does, since the selection has to survive a repaint even
    // without the pointer moving and hover never does.
    if (this._overlay) this._overlay.clearHover()
    // Trigger 1 of #_repositionOverlay: the repaint just above replaced the
    // whole canvas subtree, so whatever element the selection box used to
    // point at no longer exists -- the selection has to be re-resolved
    // against the new DOM, not merely re-measured.
    this._repositionOverlay()
  }

  // Makes every design node draggable in place -- a plain element fires no
  // `dragstart` at all without `draggable="true"` (this file's header,
  // "Native drag-and-drop"). Two passes over the JUST-painted subtree:
  //
  //   1. every [data-editor-node-id] gets draggable="true" -- these are
  //      exactly the elements #_onFrameDragStart knows how to resolve back
  //      to a tree node.
  //   2. any img, a[href], or already-draggable element NESTED inside one
  //      of those (but not a stamped element itself -- a stamped img/a
  //      keeps the draggable="true" pass 1 just gave it) gets forced to
  //      draggable="false". Without this, the BROWSER commits to
  //      natively dragging that inner image/link the instant the pointer
  //      moves over it, and there is no API to cancel that mid-drag and
  //      start a different one on the ancestor instead -- #_onFrameDragStart
  //      would simply never see a `dragstart` for the node it wraps.
  //
  // These are presentation-only DOM writes, exactly like the contenteditable
  // attribute #_beginCanvasEdit toggles: #_paintCanvas replaces the whole
  // canvas subtree from scratch on every preview response, so both passes
  // rerun (and any leftover attribute is simply discarded with the old
  // subtree) on every repaint. Never read back into the tree, never
  // reaches Tree.setNodeValue, never appears in the exported .html.erb.
  _makeCanvasDraggable(canvasEl) {
    const stamped = Array.from(canvasEl.querySelectorAll("[data-editor-node-id]"))
    stamped.forEach((el) => el.setAttribute("draggable", "true"))

    canvasEl.querySelectorAll("img, a[href], [draggable]").forEach((el) => {
      if (el.hasAttribute("data-editor-node-id")) return // a stamped element itself -- leave draggable="true"
      if (el.closest("[data-editor-node-id]")) el.setAttribute("draggable", "false")
    })
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
    this._selectFromCanvas(target.getAttribute("data-editor-node-id"))
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

  // Keyboard shortcuts, live on the frame document so they fire while the
  // user's focus/attention is on the canvas rather than some other panel:
  // Delete/Backspace deletes the selection, Escape clears it, Ctrl/Cmd+D
  // duplicates it, "p" selects its parent.
  //
  // The very first check has to be "is the user typing right now", checked
  // BEFORE looking at which key was pressed -- getting the order backwards
  // (e.g. checking `key === "Backspace"` first) would delete the selected
  // component out from under someone who is midway through backspacing a
  // typo in the canvas's own contenteditable field, or in a real form
  // control the previewed design happens to render (a text input inside a
  // card, say). #_isTextEditingTarget covers both: the canvas's own
  // in-place edit (this._canvasEditing) and any input/textarea/select/
  // contenteditable element the click landed in, whether or not this
  // controller put it there.
  _onFrameKeydown(event) {
    if (this._isTextEditingTarget(event.target)) return

    const key = event.key

    if (key === "Delete" || key === "Backspace") {
      event.preventDefault() // Backspace would otherwise navigate the frame back
      if (this._selectedNodeId) this._deleteNode(this._selectedNodeId)
      return
    }

    if (key === "Escape") {
      if (!this._selectedNodeId && !this._selectedSlotTarget && !this._selectedForeign) return
      const hadSlotTarget = !!this._selectedSlotTarget
      this._selectedSlotTarget = null
      this._selectNode(null) // also clears a foreign selection -- see #_selectNode's own doc
      if (hadSlotTarget) this._renderStructure() // #_selectNode alone doesn't touch the slot-target highlight
      return
    }

    if ((event.metaKey || event.ctrlKey) && key.toLowerCase() === "d") {
      event.preventDefault() // Ctrl/Cmd+D would otherwise bookmark the page
      if (this._selectedNodeId) this._duplicateNode(this._selectedNodeId)
      return
    }

    // Ctrl/Cmd+Z / Ctrl/Cmd+Shift+Z -- see "Undo / redo" above. Checked
    // ahead of "d" alphabetically only by coincidence of source order; both
    // return before anything below can also match the same keydown.
    if ((event.metaKey || event.ctrlKey) && key.toLowerCase() === "z") {
      event.preventDefault() // Ctrl/Cmd+Z would otherwise navigate the frame's own history
      if (event.shiftKey) {
        this._redo()
      } else {
        this._undo()
      }
      return
    }

    // "p" for parent. Picked over an arrow key (already spoken for by the
    // up/down MOVE semantics moveNodeUp/moveNodeDown carry, and reusing
    // one of them for a completely different operation -- reparenting the
    // selection upward, not reordering it among siblings -- would be
    // actively misleading) and over Tab (the browser's own focus-order key,
    // not ours to repurpose inside a document that can contain real,
    // focusable form controls from the previewed design).
    if (key === "p" || key === "P") {
      if (this._selectedNodeId) {
        event.preventDefault()
        this._selectParentOfSelection()
      }
    }
  }

  _isTextEditingTarget(target) {
    if (this._canvasEditing) return true
    if (!target || !target.tagName) return false
    if (["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return true
    return !!target.isContentEditable
  }

  // === Drag-and-drop (native, palette -> canvas AND canvas -> canvas) =======
  //
  // #paletteDragStart/#paletteDragEnd (above, near #addFromPalette) own the
  // palette-drag SOURCE side, in the parent document. #_onFrameDragStart/
  // #_onFrameDragEnd just below own the OTHER source side -- an existing
  // canvas node being dragged to reorder/reparent it -- which lives in the
  // frame document instead (dnd.js's header explains why dragstart/dragend
  // follow whichever document the drag actually started in). Everything
  // after that is the TARGET side, common to both kinds of drag, wired
  // onto the frame document in #_onFrameLoad via DnD.attachFrameDropTarget
  // and torn down in #_detachFrameListeners. See this file's header
  // ("Native drag-and-drop") for the lock this all revolves around, and
  // dnd.js's own header for the full two-documents mechanism.

  // Starts a drag on an existing, already-rendered canvas node -- the
  // frame-document mirror of #paletteDragStart. Only reachable at all
  // because #_paintCanvas stamps `draggable="true"` on every
  // [data-editor-node-id] element (a plain element is not draggable by
  // default); see this file's header for why that stamping happens on
  // every repaint rather than once. Guards against starting a drag while a
  // canvas text edit is in progress exactly like #paletteDragStart does,
  // and for the same reason -- and also no-ops (lets the browser's default
  // drag-a-text-selection behaviour proceed instead) when the pointer
  // isn't over a stamped element at all, e.g. dragging inside the frame's
  // own dead space or a piece of chrome this controller doesn't own.
  _onFrameDragStart(event) {
    if (this._canvasEditing) {
      event.preventDefault()
      return
    }

    const target = event.target.closest ? event.target.closest("[data-editor-node-id]") : null
    if (!target) return

    const nodeId = target.getAttribute("data-editor-node-id")
    const tree = this._currentTree()
    const node = tree && Tree.findNode(tree, nodeId)
    if (!node) {
      // The id doesn't resolve in the OPEN file's own tree -- foreign
      // (belongs to a different file, reached through a `partial` node --
      // see editor/workspace.js#findNodeAcrossWorkspace's own header) or
      // outright unresolvable. #_makeCanvasDraggable stamps
      // draggable="true" on every [data-editor-node-id] element
      // indiscriminately (it has no way to tell local from foreign), so
      // without this preventDefault() the browser would still start a
      // native drag nothing downstream can act on -- _dragState never gets
      // set, so every dragover/drop/dragend handler below just no-ops,
      // leaving a "drag" that visibly started but can never do anything.
      // Moving a node between files -- or moving a phantom id -- isn't an
      // operation Tree.moveNode/Tree.moveNodeTo can perform in the first
      // place (both mutate ONE tree, addressed by an id from that same
      // tree), so refusing outright is the honest behaviour here, not
      // merely a cosmetic one. See #_selectFromCanvas for the read-only
      // SELECTION counterpart of this same local/foreign/missing split.
      event.preventDefault()
      return
    }

    const label = labelFor(node)
    // sourceNodeId set (unlike #paletteDragStart's always-null) is what
    // marks this as a MOVE -- see #_applyDrop, the one place the two paths
    // actually diverge.
    this._dragState = { kind: node.kind, component: node.name || null, label, target: null, sourceNodeId: nodeId }

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", label) // Firefox requires this -- see dnd.js's header
    DnD.paintDragImage(event, label)

    if (this._overlay) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
    }
  }

  // The frame-document twin of #paletteDragEnd -- see this file's header
  // and dnd.js's for why a canvas-node drag's dragend fires here instead
  // of on the palette item. #_endDrag is idempotent, so this is a no-op on
  // top of a drop that already cleaned up via #_onFrameDrop, exactly like
  // #paletteDragEnd already is for the palette-drag case. Without this
  // listener, cancelling a canvas-node drag (Escape, dropping outside the
  // browser window) would leave `this._dragState` set forever -- and with
  // it, #_paintCanvas permanently frozen (that method's own repaint-lock
  // guard, this file's header).
  _onFrameDragEnd() {
    this._endDrag()
  }

  // Every dragover tick: hit-test the pointer against a stamped element
  // (or nothing, meaning "append to the root"), resolve where a drop would
  // land via editor/drop_target.js, remember it on this._dragState.target
  // for #_onFrameDrop to use, paint the ghost/insertion line/chip menu at
  // that position, and set the drop cursor from the resolved (advisory)
  // validity. dnd.js has already called preventDefault() on this event by
  // the time it reaches here -- without that, `drop` would never fire at
  // all.
  _onFrameDragOver(event) {
    if (!this._dragState || !this._frameDoc) return

    const hit = DnD.hitTestStamped(this._frameDoc, event.clientX, event.clientY)
    const descriptor = resolveDropTarget({
      tree: this._currentTree(),
      schema: this._schema,
      hoveredNodeId: hit ? hit.id : null,
      hoveredRect: hit ? hit.rect : null,
      pointerY: event.clientY,
      draggedKind: this._dragState.kind,
      draggedNodeId: this._dragState.sourceNodeId
    })

    this._dragState.target = descriptor
    // "move" for a canvas-node drag, "copy" for a palette drag -- has to
    // match whichever `effectAllowed` the corresponding dragstart set
    // (#_onFrameDragStart / #paletteDragStart) or the browser silently
    // coerces it to "none" regardless of `valid`, showing a permanently
    // "refused" cursor even on a legal target.
    if (event.dataTransfer) {
      const allowedEffect = this._dragState.sourceNodeId ? "move" : "copy"
      event.dataTransfer.dropEffect = descriptor.valid ? allowedEffect : "none"
    }
    this._paintDragGhost(descriptor, event)
  }

  // The pointer left the frame document entirely (dnd.js's `onLeave`,
  // fired only for that one case -- see its own header). The drag is
  // still live (dragend/drop haven't happened), but there is nothing
  // sensible left to draw a ghost/chips against, so clear all the drop
  // chrome and the last-resolved target -- if the drag re-enters the
  // frame, the very next dragover tick resolves a fresh one.
  _onFrameDragLeave() {
    if (!this._dragState) return
    this._dragState.target = null
    if (this._overlay) {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearChips()
    }
  }

  // Mutates the tree using whatever #_onFrameDragOver last resolved, then
  // ends the drag synchronously in the same handler -- #_endDrag is NOT
  // deferred to the dragend that follows, because dragend's only job here
  // is to be a safety net for when drop never fires at all (dnd.js's
  // header). A "chips" descriptor has no single target of its own (the
  // user has to release over a specific chip instead -- see
  // #_paintChips, whose buttons call #_applyDrop directly and #_endDrag
  // themselves, bypassing this handler entirely via their own
  // stopPropagation) -- releasing over the frame anywhere else while
  // chips are showing is simply not a drop, same as releasing over dead
  // space always has been.
  _onFrameDrop(event) {
    if (!this._dragState) return

    const descriptor = this._dragState.target
    if (descriptor && descriptor.position !== "chips") this._applyDrop(descriptor)

    this._endDrag()
  }

  // Performs the mutation a resolved single-target descriptor (or a chosen
  // chip -- same {parentId, container, index} shape) describes. Two
  // branches on `this._dragState.sourceNodeId`: null means this is a
  // palette drag building a brand-new node (#_buildNewNode +
  // Tree.insertAt, exactly what #_onFrameDrop always did before canvas-
  // node dragging existed); set means this is an existing node being
  // moved (Tree.moveNodeTo). Deliberately does not gate on
  // `target.valid`: validity is advisory only (drop_target.js's own
  // header) -- an "invalid" target is still handed to Tree.moveNodeTo/
  // Tree.insertAt exactly like any other edit. For moveNodeTo specifically
  // this is more than "advisory" in practice: dropping into a node's own
  // descendant is already a safe no-op at the data layer (tree.js's own
  // header on #moveNodeTo) regardless of what this file thinks `valid`
  // should say, so there is nothing here that NEEDS gating for
  // correctness -- only the ghost/chip's appearance depends on it.
  _applyDrop(target) {
    if (!target || !target.parentId) return

    if (this._dragState.sourceNodeId) {
      const sourceId = this._dragState.sourceNodeId
      this._updateTree((tree) => Tree.moveNodeTo(tree, sourceId, target.parentId, target.container, target.index))
    } else {
      const node = this._buildNewNode(this._dragState.kind, this._dragState.component)
      if (!node) return
      this._updateTree((tree) => Tree.insertAt(tree, target.parentId, target.container, target.index, node))
    }
    this._schedulePreview()
  }

  // Renders the ghost box + insertion line, OR the chip menu, for the drop
  // `descriptor` resolved this tick -- exactly one of the two is ever
  // showing at once, so each branch below clears the other's chrome before
  // (or instead of) drawing its own. Four cases, in the order checked:
  //
  //   1. no descriptor at all (drag left the frame, #_onFrameDragLeave) --
  //      clear everything.
  //   2. `position: "chips"` -- delegate to #_paintChips; no ghost/
  //      insertion line for this tick.
  //   3. `position: "into"` -- landing INSIDE the hovered element itself
  //      (a row/column/fragment taking children directly), so the ghost is
  //      drawn as that element's own full rect rather than a sliver beside
  //      it, and there is no edge to draw an insertion line against.
  //   4. `position: "before"/"after"` (descriptor.anchorRect set) --
  //      original phase-1 behaviour: insertion line flush with the
  //      resolved edge, ghost sized off the hovered element's own width,
  //      sitting just outside it on the correct side.
  //   5. `position: "append"` (no hovered element at all -- empty canvas,
  //      or the pointer over dead space) -- no insertion line, ghost sized
  //      off the canvas element itself, at ROOT_GHOST_HEIGHT (drop_target.
  //      js's own constant, so the two never drift apart).
  _paintDragGhost(descriptor, event) {
    if (!this._overlay) return
    if (!descriptor) {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearChips()
      return
    }

    if (descriptor.position === "chips") {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._paintChips(descriptor, event)
      return
    }
    this._overlay.clearChips()

    if (descriptor.position === "into") {
      this._overlay.clearInsertionLine()
      if (descriptor.anchorRect) {
        const anchor = descriptor.anchorRect
        this._overlay.setGhost(rectOf(anchor.left, anchor.top, anchor.width, anchor.height), this._dragState.label, descriptor.valid)
      } else {
        this._overlay.clearGhost()
      }
      return
    }

    if (descriptor.anchorRect) {
      const anchor = descriptor.anchorRect
      const height = Math.max(20, Math.min(ROOT_GHOST_HEIGHT, anchor.height))
      const top = descriptor.position === "before" ? anchor.top - height : anchor.bottom

      this._overlay.setInsertionLine(descriptor.insertionRect)
      this._overlay.setGhost(rectOf(anchor.left, top, anchor.width, height), this._dragState.label, descriptor.valid)
      return
    }

    this._overlay.clearInsertionLine()
    const canvasEl = this._frameDoc && this._frameDoc.getElementById("tabler-ui-editor-canvas")
    if (!canvasEl) {
      this._overlay.clearGhost()
      return
    }
    const canvasRect = canvasEl.getBoundingClientRect()
    const top = Math.max(canvasRect.top, canvasRect.bottom - ROOT_GHOST_HEIGHT)
    this._overlay.setGhost(rectOf(canvasRect.left, top, canvasRect.width, ROOT_GHOST_HEIGHT), this._dragState.label, descriptor.valid)
  }

  // Renders the "drop into..." chip menu near the drag's current cursor
  // position for a `position: "chips"` descriptor (drop_target.js's own
  // header explains why chips anchor to the cursor rather than to a
  // container's own rect: an empty slot renders no DOM to anchor to at
  // all). Only VALID chips are ever handed to the overlay -- drop_target.js's
  // #legalChips already dropped every kind-illegal or own-subtree
  // candidate before this ever runs, but a chip can still fail the
  // node-count/depth limit check that runs per-chip alongside it
  // (drop_target.js#validateTarget), so this filter is the one still doing
  // real work, not a leftover no-op. Each surviving chip's onDrop applies
  // that one chip's own {parentId, container, index} via #_applyDrop and
  // ends the drag itself -- overlay.js's chip buttons already
  // stopPropagation their own drop event, so this never also runs through
  // #_onFrameDrop for the same release.
  _paintChips(descriptor, event) {
    const chips = (descriptor.chips || []).filter((chip) => chip.valid)
    if (chips.length === 0) {
      this._overlay.clearChips()
      return
    }

    const cursorRect = rectOf(event.clientX, event.clientY, 0, 0)
    const buttons = chips.map((chip) => ({
      label: chip.label,
      onDrop: () => {
        this._applyDrop(chip)
        this._endDrag()
      }
    }))
    // Same "move" (canvas-node source) vs "copy" (palette source) split
    // #_onFrameDragOver's own dropEffect uses, kept in sync with it here --
    // see overlay.js#setChips's own comment for why this has to be passed
    // through rather than guessed at inside overlay.js.
    const dropEffect = this._dragState.sourceNodeId ? "move" : "copy"
    this._overlay.setChips(cursorRect, buttons, dropEffect)
  }

  // The one place a drag's lock is released. Idempotent -- safe to call
  // from #_onFrameDrop and a chip's own onDrop (drop already happened,
  // tree already mutated), and from #paletteDragEnd/#_onFrameDragEnd
  // (dragend, the guaranteed-once terminator for each of the two source
  // documents -- see this file's header) -- none of the four cares whether
  // one of the others already ran. Ends with an explicit #_paintCanvas()
  // call rather than leaving the next scheduled preview to flush it:
  // unlike ending a text edit (#_endCanvasEdit always calls
  // #_schedulePreview itself), a CANCELLED drag (dragend with no drop)
  // schedules no new preview at all, so nothing else would ever paint a
  // this._lastHtml that arrived from an in-flight request while the lock
  // was held.
  _endDrag() {
    if (!this._dragState) return
    this._dragState = null
    if (this._overlay) {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearChips()
    }
    this._paintCanvas()
  }

  // === Hover =================================================================
  //
  // Driven from pointermove rather than mouseover/mouseout: enter/leave
  // events fire at every child-element boundary, so naively toggling the
  // hover box on mouseover/mouseout flickers as the pointer crosses
  // interior elements that belong to the same logical node (e.g. an icon
  // inside a button inside a card -- three elements, one
  // [data-editor-node-id]). Recomputing "what node is under the pointer
  // right now" from raw coordinates on every move sidesteps that entirely:
  // the answer only changes when the pointer actually crosses into a
  // DIFFERENT node's rendered element, never on an interior boundary
  // within the same one.
  //
  // Throttled to one measurement per animation frame rather than one per
  // pointermove event -- a mouse can fire dozens of these between two
  // repaints, and each one here costs an elementFromPoint (hit test) plus,
  // on a match, a getBoundingClientRect (layout read); doing that on every
  // raw event is exactly the "performance problem on a large design" this
  // is meant to avoid. #_pendingHoverPoint always holds the LATEST pointer
  // position seen since the last frame fired, so nothing is lost by
  // coalescing -- only intermediate positions between two same-frame
  // events are, and those were never going to be visibly distinct anyway.
  _onFramePointerMove(event) {
    this._pendingHoverPoint = { x: event.clientX, y: event.clientY }
    if (this._hoverRafId != null) return // already scheduled for this frame

    const view = this._frameDoc.defaultView
    if (!view) return
    this._hoverRafId = view.requestAnimationFrame(() => {
      this._hoverRafId = null
      this._updateHoverFromPoint(this._pendingHoverPoint)
    })
  }

  // "pointerout" bubbles (unlike pointerleave), so one listener directly on
  // `doc` sees every element the pointer leaves -- but most of those are
  // the pointer moving from one element to another INSIDE the frame, which
  // is not "the pointer left the frame" and must not clear the hover the
  // very next pointermove is about to redraw anyway. `relatedTarget` is
  // the element the pointer entered; it is null exactly when the pointer
  // left the document altogether (out through the iframe's own edge, or
  // into browser chrome), which is the one case this clears for.
  _onFramePointerOut(event) {
    if (event.relatedTarget) return
    this._cancelHoverFrame()
    this._setHover(null)
  }

  _cancelHoverFrame() {
    if (this._hoverRafId != null && this._frameDoc && this._frameDoc.defaultView) {
      this._frameDoc.defaultView.cancelAnimationFrame(this._hoverRafId)
    }
    this._hoverRafId = null
  }

  _updateHoverFromPoint(point) {
    if (!point || !this._frameDoc) {
      this._setHover(null)
      return
    }
    const el = this._frameDoc.elementFromPoint(point.x, point.y)
    // pointer-events: auto on the toolbar (and nothing else in this
    // overlay) means elementFromPoint correctly returns a toolbar button
    // when the cursor is over one -- .closest("[data-editor-node-id]")
    // then finds nothing (the toolbar isn't part of the design), so
    // hovering the toolbar itself correctly shows no hover box rather than
    // highlighting whatever design element happens to sit underneath it.
    const target = el && el.closest ? el.closest("[data-editor-node-id]") : null
    this._setHover(target ? target.getAttribute("data-editor-node-id") : null, target)
  }

  // Resolves `id` to a live element and label exactly like
  // #_highlightCanvasSelection does for the selection box, with two added
  // rules: never draw the hover box on the element that is ALREADY the
  // selection (two boxes stacked on one element reads as a rendering bug,
  // not as "this element is both selected and hovered" -- the selection
  // box alone already communicates that, whether that selection is local
  // or foreign), and label a FOREIGN element distinctly (see
  // #_foreignHoverLabel) -- hovering one should read as different from
  // hovering an editable one even before a click resolves it either way.
  // `el` is passed through from #_updateHoverFromPoint when the caller
  // already has it (avoids a redundant querySelector);
  // #_onFramePointerOut calls this with neither, which the `el ||`
  // fallback below treats the same as "not found".
  _setHover(id, el) {
    if (!this._overlay) return
    if (!id || id === this._selectedNodeId || (this._selectedForeign && id === this._selectedForeign.id)) {
      this._overlay.clearHover()
      return
    }
    const element = el || (this._frameDoc && this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(id)}"]`))
    if (!element) {
      this._overlay.clearHover()
      return
    }

    const tree = this._currentTree()
    const isLocal = !!(tree && Tree.findNode(tree, id))
    const label = isLocal ? this._selectionLabel(id) : this._foreignHoverLabel(id)
    this._overlay.setHover(element.getBoundingClientRect(), label)
  }

  // The distinct hover label for an element that belongs to a different
  // file (see #_resolveNodeId / editor/workspace.js#findNodeAcrossWorkspace).
  // A full cross-file search on every hover is affordable here the same
  // way it is in #_resolveNodeId: this only runs for an id #_setHover has
  // already failed to find in the OPEN file's own tree (i.e. every LOCAL
  // hover, the overwhelmingly common case, never reaches this at all), and
  // it's bounded by rAF-throttled pointermove the same as the rest of
  // hover handling (#_onFramePointerMove's own header). Falls back to a
  // generic "External" tag rather than treating "resolves nowhere at all"
  // as an error -- the label is cosmetic only, so a slightly generic tag
  // for a genuinely dangling id costs nothing correctness-wise.
  _foreignHoverLabel(id) {
    const found = Workspace.findNodeAcrossWorkspace(this._workspace.files, this._workspace.open, id)
    return found ? `External: ${labelFor(found.node)}` : "External"
  }

  _beginCanvasEdit(el) {
    const nodeId = el.getAttribute("data-editor-node-id")
    const tree = this._currentTree()
    const node = tree && Tree.findNode(tree, nodeId)
    if (!node) {
      // Same local/foreign/missing split #_selectFromCanvas resolves for a
      // single click -- a foreign or phantom id has no in-canvas edit to
      // begin (there's no LOCAL node/path to write Tree.setNodeValue
      // against), but it can still be SELECTED read-only, so the inspector
      // tells the user why nothing happened instead of the dblclick simply
      // doing nothing at all.
      this._selectedSlotTarget = null
      this._selectFromCanvas(nodeId)
      return
    }

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

  // Selects a node already known to live in the OPEN file's own tree (or
  // clears the selection, for `id === null`) -- every caller here passes
  // an id it already resolved itself: the Structure panel's own rows, the
  // canvas toolbar, #_selectParentOfSelection, #_duplicateNode, Escape/
  // Delete. A canvas click/dblclick can NOT assume that -- the element
  // clicked may belong to a different file entirely (see
  // #_selectFromCanvas, the one caller that resolves an untrusted id
  // FIRST and only reaches this method for the local case).
  _selectNode(id) {
    this._selectedNodeId = id
    this._selectedForeign = null
    this._renderInspector()
    this._highlightCanvasSelection(id)
    this._highlightStructureSelection(id)
    // A hover box left over from just before this selection was made could
    // now be sitting on the very element that's about to become the
    // selection -- #_setHover already refuses to draw hover on top of the
    // selection, but only the NEXT pointermove would apply that check.
    // Clearing here means the hover box never has a chance to render on
    // the same element the selection box just claimed, even for one frame.
    if (this._overlay) this._overlay.clearHover()
  }

  // Resolves a raw `data-editor-node-id` value seen on the canvas
  // (#_onFrameClick / #_onFrameDblClick / #_onFrameDragStart) to one of
  // three outcomes:
  //
  //   - LOCAL: found in the OPEN file's own tree -- every existing
  //     single-file assumption elsewhere in this controller already holds,
  //     so the caller can treat `id` exactly like it always has.
  //   - FOREIGN: found in some OTHER file's tree, reached by following a
  //     `partial` node (Workspace.findNodeAcrossWorkspace's own header --
  //     node ids are only unique WITHIN one file). `context` is looked up
  //     the same way #inspectorHtml already resolves it for a local
  //     selection (Tree.findNodeContext), just against the file the node
  //     was actually found in rather than the open one, so a foreign
  //     component/builder_item's read-only fields (editor/inspector.js)
  //     can be built exactly like a local one's would be.
  //   - MISSING: not found anywhere in the whole reachable workspace -- a
  //     stale id, or junk.
  //
  // The one caller-visible id (`id`) is the SAME value in all three cases;
  // what differs is which tree (if any) it resolves against.
  _resolveNodeId(id) {
    if (!id) return { kind: "missing" }

    const tree = this._currentTree()
    const localNode = tree && Tree.findNode(tree, id)
    if (localNode) return { kind: "local", node: localNode }

    const found = Workspace.findNodeAcrossWorkspace(this._workspace.files, this._workspace.open, id)
    if (!found) return { kind: "missing" }

    const foundTree = this._workspace.files[found.path].tree
    const contextResult = Tree.findNodeContext(this._schema, foundTree, id)
    return { kind: "foreign", node: found.node, path: found.path, context: contextResult ? contextResult.context : null }
  }

  // The canvas-click/dblclick counterpart of #_selectNode -- see that
  // method's own doc and #_resolveNodeId's header for the local/foreign/
  // missing split this applies BEFORE trusting a clicked element's id at
  // all. #_selectNode itself is untouched and stays the right call for
  // every OTHER caller in this file (they only ever pass an id already
  // known to live in the open file's own tree).
  _selectFromCanvas(id) {
    const resolved = this._resolveNodeId(id)

    if (resolved.kind === "local") {
      this._selectNode(id)
      return
    }

    if (resolved.kind === "foreign") {
      this._selectedNodeId = null
      this._selectedForeign = { id, path: resolved.path, node: resolved.node, context: resolved.context }
      this._renderInspector()
      this._highlightForeignSelection(id)
      this._highlightStructureSelection(null) // the Structure panel has no row for a node outside this file
      if (this._overlay) this._overlay.clearHover()
      return
    }

    // MISSING -- a stale or otherwise unresolvable id. Selecting nothing
    // (the same end state Escape / a delete already produce) is the honest
    // outcome here; the alternative -- leaving whatever was selected
    // before untouched, or drawing a selection box against an id that
    // resolves to nothing -- is exactly the "phantom selection" bug this
    // method exists to fix (see this feature's own task note: clicking
    // such an element used to call #_selectNode with no existence check at
    // all).
    this._selectNode(null)
  }

  // Resolves `id` to a live element, label and toolbar-button list, and
  // hands them to the overlay -- editor/overlay.js itself knows nothing
  // about node ids or the tree (see that file's header), so this is the
  // one place that bridges the two. Clears the selection box (and the
  // toolbar with it), rather than drawing one at a stale position,
  // whenever there's nothing to select or the selected node's element
  // isn't currently rendered (it can be selected without being on screen
  // -- e.g. the node lives inside a slot/branch the current tree state
  // doesn't render).
  _highlightCanvasSelection(id) {
    if (!this._overlay) return
    const el = (id && this._frameDoc)
      ? this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(id)}"]`)
      : null

    if (!el) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
      return
    }
    const rect = el.getBoundingClientRect()
    this._overlay.setSelection(rect, this._selectionLabel(id))
    this._overlay.setToolbar(rect, this._toolbarButtons(id))
  }

  // The foreign-selection counterpart of #_highlightCanvasSelection --
  // draws the same solid selection box (still using overlay.js's own
  // setSelection/clearSelection -- nothing here asks overlay.js for a new
  // visual, see this feature's own constraint on that module), so
  // something clearly reads as selected, but:
  //
  //   - labels it "External: ..." rather than the plain label a local
  //     selection gets, so it reads as distinct at a glance (the same
  //     "External" convention #_foreignHoverLabel uses for hover).
  //   - never calls setToolbar. Move up/down/duplicate/delete
  //     (#_toolbarButtons) all mutate the OPEN file's tree by node id
  //     (#_moveNode/#_duplicateNode/#_deleteNode), and this id does not
  //     exist in that tree at all -- offering those actions here would
  //     either silently no-op or, worse, act on whatever unrelated node
  //     the open tree happens to have at a colliding id.
  _highlightForeignSelection(id) {
    if (!this._overlay) return
    const el = this._frameDoc ? this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(id)}"]`) : null

    if (!el) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
      return
    }

    const label = this._selectedForeign ? labelFor(this._selectedForeign.node) : ""
    this._overlay.setSelection(el.getBoundingClientRect(), `External: ${label}`)
    this._overlay.clearToolbar()
  }

  // The canvas toolbar's five actions, in display order. Built fresh on
  // every call (see overlay.js#setToolbar's own header for why that's
  // correct rather than wasteful) so each onClick closes over the id this
  // call was made with -- there is never a stale nodeId left over from a
  // previous selection baked into one of these callbacks.
  //
  // Move up/down and delete route through the exact same #_moveNode/
  // #_deleteNode bodies the Structure panel's row buttons call (see those
  // methods' own header) -- this toolbar is a second way to trigger them,
  // not a second implementation of them.
  _toolbarButtons(id) {
    return [
      { label: "&#8598;", title: "Select parent (p)", onClick: () => this._selectParentOfSelection() },
      { label: "&#9650;", title: "Move up", onClick: () => this._moveNode(id, "up") },
      { label: "&#9660;", title: "Move down", onClick: () => this._moveNode(id, "down") },
      { label: "Duplicate", title: "Duplicate (Ctrl/Cmd+D)", onClick: () => this._duplicateNode(id) },
      { label: "&times;", title: "Delete (Del)", onClick: () => this._deleteNode(id) }
    ]
  }

  // Stimulus action (data-action="shown.bs.tab->tabler-ui--docs-editor#
  // repositionOverlay" on the Preview tab's own anchor, editor/show.html.erb)
  // -- a public wrapper because a data-action target has to be a public
  // method, unlike the other three triggers below, which call the private
  // one directly from inside this controller.
  repositionOverlay() {
    this._repositionOverlay()
  }

  // A DOMRect returned by getBoundingClientRect() is a one-time snapshot,
  // not a live value -- anything that can move the selected element out
  // from under an already-drawn selection box, or remove it from the DOM
  // entirely, has to re-resolve the id to an element and re-measure rather
  // than trust the box that's already on screen. Re-running
  // #_highlightCanvasSelection against the current this._selectedNodeId
  // does exactly that (it already re-queries the DOM and re-measures on
  // every call) -- this method exists only to give the four call sites
  // that need "re-derive and re-apply" a shared, self-describing name
  // rather than each reaching for #_highlightCanvasSelection directly.
  //
  // The four triggers: the tail of #_paintCanvas (the canvas subtree was
  // just replaced), "scroll" on the frame document and "resize" on the
  // frame's own window (both registered in #_onFrameLoad, removed in
  // #_detachFrameListeners), and Bootstrap's shown.bs.tab firing on the
  // Preview tab's anchor (a display: none tab-pane collapses the iframe's
  // layout and does not reliably fire a `resize` of its own).
  //
  // A foreign selection (#_selectedForeign) re-derives through
  // #_highlightForeignSelection instead -- same "re-resolve and re-apply"
  // need, just against the OTHER box-drawing method (#_selectFromCanvas
  // never touches _selectedNodeId for a foreign selection, so
  // #_highlightCanvasSelection alone would just clear the box here).
  _repositionOverlay() {
    if (this._selectedForeign) {
      this._highlightForeignSelection(this._selectedForeign.id)
      return
    }
    this._highlightCanvasSelection(this._selectedNodeId)
  }

  // labelFor (editor/structure.js) is the same function the Structure
  // panel already uses for a node's own row label -- reused here rather
  // than re-deriving a second "how do we describe this node" rule that
  // could drift out of sync with what the Structure tab says about the
  // same node.
  _selectionLabel(id) {
    const tree = this._currentTree()
    const node = tree && Tree.findNode(tree, id)
    return node ? labelFor(node) : ""
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

  // Every structural mutation in this controller funnels through here --
  // it's the one place an undo snapshot can be pushed with a guarantee
  // that nothing bypasses it (see #_pushUndoSnapshot below).
  //
  // The snapshot push is skipped in two cases, both to keep the bounded
  // undo stack full of MEANINGFUL steps a user would actually want to
  // press Ctrl+Z back through, rather than noise:
  //
  //   - a true no-op: `newTree` compares CONTENT-equal to `previousTree`.
  //     Not a reference check (`!==`) -- several tree.js mutators return
  //     `cloneTree(tree)` -- a fresh object, same content -- for their own
  //     no-op case (moveNodeTo's own header spells this out: dropping a
  //     node into its own subtree, an id that doesn't resolve, a slot
  //     that's already occupied, ...), so a reference check would wrongly
  //     treat every one of those as a real edit.
  //   - `rebuildStructure: false`, which only #_onCanvasInput passes, for
  //     the per-KEYSTROKE write behind an in-canvas text edit. Were this
  //     not excluded, typing one sentence would push a dozen snapshots and
  //     -- bounded stack -- shove the actually-interesting PRE-edit state
  //     (the one before the user started typing) off the end before the
  //     edit was even finished. Nothing is lost by skipping it: Ctrl+Z is
  //     already inert for the whole duration of that edit anyway
  //     (#_onFrameKeydown's #_isTextEditingTarget guard), so there is no
  //     user-visible "undo" these per-keystroke snapshots could ever have
  //     served.
  _updateTree(mutator, { rebuildStructure = true } = {}) {
    const path = this._workspace.open
    if (!path || !this._workspace.files[path]) return

    const previousTree = this._workspace.files[path].tree
    const newTree = mutator(previousTree)

    if (rebuildStructure && JSON.stringify(previousTree) !== JSON.stringify(newTree)) {
      this._pushUndoSnapshot()
    }

    this._workspace = { ...this._workspace, files: { ...this._workspace.files, [path]: { tree: newTree } } }
    this._persist()
    if (rebuildStructure) this._renderStructure()
  }

  // === Undo / redo ===========================================================
  //
  // See #_updateTree's own comment for where snapshots are pushed and what
  // is deliberately excluded. Both stacks hold whole WORKSPACE objects, by
  // reference -- #_updateTree only ever touches the currently open file's
  // own tree, but snapshotting the whole workspace (rather than just that
  // one file's tree) means an undo/redo can never end up mismatched
  // against which file was open when the snapshot was taken.

  _undo() {
    if (this._undoStack.length === 0) return
    const previous = this._undoStack.pop()
    this._pushToBoundedStack(this._redoStack, this._workspace)
    this._restoreWorkspace(previous)
  }

  _redo() {
    if (this._redoStack.length === 0) return
    const next = this._redoStack.pop()
    this._pushToBoundedStack(this._undoStack, this._workspace)
    this._restoreWorkspace(next)
  }

  _pushToBoundedStack(stack, workspace) {
    stack.push(workspace)
    if (stack.length > UNDO_STACK_LIMIT) stack.shift()
  }

  // The one place a snapshot is pushed pre-mutation (#_updateTree above).
  // A fresh edit invalidates whatever redo history existed -- the standard
  // undo/redo convention: a branch, once diverged from by a new edit,
  // doesn't come back.
  _pushUndoSnapshot() {
    this._pushToBoundedStack(this._undoStack, this._workspace)
    this._redoStack = []
  }

  // Shared tail for #_undo/#_redo: swap the whole workspace in, persist it
  // (so a Turbo reconnect / reload sees the restored state, exactly like
  // every other write in this file), refresh every panel, and re-point the
  // live preview at it. Selection is revalidated rather than carried over
  // blindly -- the node (or foreign node) that was selected before the
  // swap may not exist in the restored tree at all (undoing an ADD, most
  // obviously) -- and a selection pointing at nothing is exactly the
  // "phantom selection" #_selectFromCanvas already exists to avoid on the
  // canvas-click path.
  _restoreWorkspace(workspace) {
    // An in-progress canvas text edit points at a DOM element from the
    // subtree about to be replaced wholesale by the schedulePreview below
    // -- end it outright (not via #_endCanvasEdit, which would itself
    // schedule a redundant preview/structure refresh on top of the full
    // refresh this method already does) rather than let it keep pointing
    // at an element that's about to be torn out from under it.
    if (this._canvasEditing) {
      this._canvasEditing.element.removeAttribute("contenteditable")
      this._canvasEditing = null
    }

    this._workspace = workspace

    const tree = this._currentTree()
    if (this._selectedNodeId && !(tree && Tree.findNode(tree, this._selectedNodeId))) {
      this._selectedNodeId = null
    }
    if (this._selectedForeign &&
        !Workspace.findNodeAcrossWorkspace(this._workspace.files, this._workspace.open, this._selectedForeign.id)) {
      this._selectedForeign = null
    }
    this._selectedSlotTarget = null

    this._persist()
    this._renderToolbarFilename()
    this._renderExplorer()
    this._renderStructure()
    this._renderInspector()
    this._repositionOverlay()
    this._schedulePreview(true)
  }

  // Bumped on every write, so an in-flight preview can tell whether the
  // workspace it was sent still describes the workspace that exists now.
  // See #_handlePreviewResult for why that matters.
  _persist() {
    this._workspaceVersion = (this._workspaceVersion || 0) + 1
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
    this.inspectorTarget.innerHTML = inspectorHtml(
      this._schema, this._currentTree(), this._selectedNodeId, this._selectedSlotTarget, this._selectedForeign
    )
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
