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
//
// ## Layout guides
//
// A half-built design is hard to aim a drop at: an empty card renders
// ~2px tall, an empty row/column collapses to 0px, an empty root-shared
// component (card_group, badge_list, alert, ribbon -- see drop_target.js's
// own ROOT_SHARED_EMPTY_COMPONENTS) collapses to 0px too, for a related but
// distinct reason (its slot content renders straight into the component's
// own root, with no dedicated wrapper for even a decorated marker to land
// on) -- nothing on screen to show where a slot or a container even is.
// `#_guidesEnabled` (loaded from localStorage, default on --
// #_loadGuidesEnabled) controls whether the next preview request asks the
// server to decorate its HTML with `data-editor-slot`/`data-editor-slot-
// shared` markers (Editor::Renderer's own `decorate:` flag) and whether
// #_repositionGuides draws anything from them. See that method's own doc
// for the full trigger list and #overlay.js#setGuides for how an
// unbounded, recomputed-on-scroll rect set stays cheap. Rows/columns (and,
// as of this fix, an empty root-shared component) need no server help at
// all for THIS part -- #_stampEmptyContainers gives each one a
// decoration-only min-height class (editor_canvas.css) purely from the
// TREE, so it has real screen space to be hit-tested against and, when
// guides are on, something for its own guide box to outline -- applied
// unconditionally, guides on or off, for the same reason
// editor_canvas.css's own canvas gutter is (see that rule's own comment):
// having somewhere to aim a drop is a usability floor, not a decoration
// preference, and an invisible-and-unreachable-at-rest component is a
// worse problem than an un-outlined one. What guides being ON adds on top
// is purely the dotted outline + label -- #_collectGuideRects' own
// `[data-editor-slot-shared]` query, which only exists in the DOM once
// this same min-height has given the marked element real geometry to
// report.
//
// ## Drag-only growth: something to aim at
//
// #_stampEmptyContainers (just above) already solves "nothing to outline"
// for an empty row/column, permanently, at every repaint. It does not
// solve "nothing to AIM AT": that same empty container's own top/bottom
// edge bands (drop_target.js's BEFORE_FRACTION/AFTER_FRACTION) are a
// couple of pixels deep at 0-2px, and a `component`-kind element (a card
// with nothing in it, say) gets no min-height stamp at all, empty or not.
// #_growSmallDropTargets fixes this for the DURATION OF A DRAG ONLY, one
// pass at drag start (#paletteDragStart, #_onFrameDragStart) over every
// currently-stamped element: anything rendering under drop_target.js's own
// DRAG_GROW_MIN_SIZE in height gets a drag-only min-height class, same for
// width -- kept as two independent classes rather than one so a wide-but-
// short banner only grows taller and a narrow-but-tall sidebar only wider.
// Measured once, like guides' own trigger list explains is safe for the
// same reason: the canvas is frozen for a drag's whole duration
// (#_paintCanvas is a no-op while `_dragState` is set), so nothing this
// method measures becomes stale before the drag ends. #_shrinkGrownDropTargets
// undoes it explicitly in #_endDrag -- not left to the next repaint's
// innerHTML replacement to clean up incidentally, since that repaint isn't
// guaranteed to run (a drop's own preview is debounced; #_paintCanvas
// itself no-ops if no preview has ever landed yet).
//
// Growing an element changes layout out from under every guide rect
// already on screen -- #_growSmallDropTargets ends with exactly ONE
// #_repositionGuides call to catch them up, same "measure once, not per
// dragover tick" discipline #_repositionGuides' own doc already holds
// scroll/resize to.
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
import { resolveDropTarget, ROOT_GHOST_HEIGHT, DRAG_GROW_MIN_SIZE, isEmptyRootSharedComponent } from "controllers/tabler_ui/docs/editor/drop_target"

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

// table's declarative `sort_url:` (see docs/lib/tabler_ui/docs/editor/tree.rb
// #normalize_declarative_sort_url) only survives a preview round-trip when
// its shape already satisfies Tree's own rules -- simple mode needs all
// three of path/sortParam/dirParam non-empty, pattern mode needs a pattern
// carrying both {key} and {dir}. Anything short of that isn't merely
// "incomplete", it gets DELETED the next time the tree is normalized, which
// is exactly the trap this whole fix closes. These are the two places this
// file ever writes a sort_url value nobody typed -- #toggleColumnSort
// (ticking "Sortable" with no sort_url configured at all) and
// #setSortUrlMode (picking a mode with a field still unset) -- so both draw
// from the same already-valid defaults rather than each guessing its own.
// "sort"/"dir" are the conventional query-param names; "/" and
// "/{key}/{dir}" are harmless placeholders a user is expected to replace
// with their own route once they see the field.
const DEFAULT_SIMPLE_SORT_URL = { mode: "simple", path: "/", sortParam: "sort", dirParam: "dir" }
const DEFAULT_PATTERN_SORT_URL = { mode: "pattern", pattern: "/{key}/{dir}" }

export default class extends Controller {
  static targets = ["explorer", "palette", "structure", "code", "inspector", "frame", "errors", "filename", "guides"]
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
    // Layout guides: whether the next preview request asks the server to
    // decorate its HTML with ghost-outline markers (Renderer's own
    // `decorate:` flag -- see EditorController#preview's doc for the
    // request-key name this reads back). Loaded from localStorage,
    // default ON (see #_loadGuidesEnabled), and mirrored onto the
    // toolbar's own toggle just below so a reload shows the same state it
    // was left in rather than always starting from the server-rendered
    // `checked` default. #_guidesRafId is the scroll-coalescing lock
    // #_scheduleGuidesReposition/#_cancelGuidesFrame manage, the guides
    // equivalent of #_hoverRafId above.
    this._guidesEnabled = this._loadGuidesEnabled()
    this._guidesRafId = null
    if (this.hasGuidesTarget) this.guidesTarget.checked = this._guidesEnabled

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

    // Give any too-small-to-aim-at element real edge bands for the rest of
    // this drag -- see this file's header, "Drag-only growth". Runs from
    // the parent document (this handler fired on a palette item, not
    // inside the frame), but the elements it measures/grows are the
    // frame's own -- #_growSmallDropTargets reaches into `this._frameDoc`
    // itself rather than needing anything from `event`.
    this._growSmallDropTargets()

    // Hide the selection box/toolbar for the duration of the drag --
    // #_endDrag's tail (via #_paintCanvas) restores them once the lock
    // lifts. this._selectedNodeId itself is untouched, so the selection
    // that was live before the drag started is still live after it ends.
    // Guides are deliberately NOT cleared here (see #_repositionGuides'
    // own doc for the fuller reasoning): an empty container is exactly as
    // invisible mid-drag as it is at rest, and dragging a component into
    // one is the main reason to want its guide drawn in the first place.
    // #_paintCanvas stays a no-op for as long as this._dragState is set
    // (this file's header, "Native drag-and-drop"), so the canvas subtree
    // is never REPLACED underneath a drag -- no element is destroyed or
    // recreated, so the guide rects already on screen stay pointed at the
    // same real elements throughout. #_growSmallDropTargets just above is
    // the one deliberate exception to "nothing changes": it can resize an
    // element in place (this file's header, "Drag-only growth"), which is
    // exactly why that method ends with its own single #_repositionGuides
    // call rather than leaving this method to also trigger one -- by the
    // time control reaches here, growth (if any) has already happened and
    // guides are already caught up, so there is nothing left for dragstart
    // itself to redraw. What DOES need to keep working for the rest of the
    // drag is #_overlay.setGuidesMuted
    // below, purely visual (recedes the existing boxes so the drag's own
    // ghost/insertion-line/chip chrome reads clearly on top -- see
    // editor_canvas.css's .docs-editor-canvas-guides-muted), and the
    // scroll-triggered reposition #_scheduleGuidesReposition already wires
    // up (this._dragState no longer suppresses it -- scrolling, including
    // drag-edge auto-scroll, is the one thing that genuinely moves an
    // already-correct rect out from under its container).
    if (this._overlay) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
      this._overlay.setGuidesMuted(true)
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

    // this._schema lets Tree.removeNode rebalance a row's remaining
    // columns back to equal widths when `nodeId` names a column being
    // deleted straight out of an otherwise-uniform row (see that
    // function's own header) -- passing null/undefined here would just
    // fall back to the old plain-splice behaviour, not throw.
    this._updateTree((tree) => Tree.removeNode(tree, nodeId, this._schema))
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

  // Editing "key" gets one extra step the other plain COLUMN_FIELDS
  // (label/class/sort itself) don't: keeping an auto-seeded `sort` in
  // step with it. #toggleColumnSort seeds `sort` as a literal copy of
  // `key` (`columns[index].key || ""`) the moment the checkbox is
  // ticked -- if that happens before `key` has been typed, `sort` is
  // seeded "". Ticking never revisited afterward, so without this,
  // typing the key next leaves the tree at `{ key: "name", sort: "" }`:
  // Table::Component#sortable? is `col[:sort].present?`, so `""` reads
  // as NOT sortable while the checkbox -- keyed off `col.sort != null`
  // in inspector.js#columnSortFieldHtml -- stays visibly checked. Same
  // failure shape as the sort_url seeding fix above: the panel showing a
  // state the tree doesn't actually have.
  //
  // The fix is to treat "sort still equals the key's PREVIOUS value" as
  // the signal that `sort` is still the auto-seeded copy (never
  // diverged), and carry that same edit over to `sort` too. That
  // deliberately does NOT fire when `sort` has been hand-typed to
  // something other than `key` (see #columnSortFieldHtml's own comment --
  // Table::Component#sorted? never requires the two to match, a column
  // can render one field and sort by another) -- a `sort` that no longer
  // equals the old `key` is evidence of exactly that, so it's left alone.
  //
  // Clearing `key` back to empty is the one case worth calling out: if
  // `sort` was still the auto-seeded copy, syncing it to match would
  // write `sort: ""` right back -- the very state this fix exists to
  // avoid. A column with no key to render can't sensibly claim a sort
  // key it never chose for itself, so `sort` (and with it the checkbox)
  // is dropped instead of carrying an empty string forward.
  updateColumnField(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption
    const index = Number(el.dataset.editorIndex)
    const field = el.dataset.editorField

    // Only set when editing "key" actually moves `sort` too -- that's
    // also the only case where the checkbox/sort-key-input markup needs
    // rebuilding; a plain label/class/sort edit changes no other control.
    let sortWasSynced = false

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const columns = Array.isArray(current) ? current.map((c) => ({ ...c })) : []
      if (!columns[index]) columns[index] = {}

      if (field === "key") {
        const oldKey = columns[index].key != null ? columns[index].key : ""
        const sortIsAutoSeededCopy = columns[index].sort != null && columns[index].sort === oldKey
        if (sortIsAutoSeededCopy) {
          if (el.value === "") {
            delete columns[index].sort
          } else {
            columns[index].sort = el.value
          }
          sortWasSynced = true
        }
      }

      if (el.value === "") {
        delete columns[index][field]
      } else {
        columns[index][field] = el.value
      }
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
    })
    if (sortWasSynced) this._renderInspector()
    this._schedulePreview()
  }

  // The "Sortable" checkbox in editor/inspector.js#columnSortFieldHtml --
  // a dedicated action rather than #updateColumnField because it has to
  // DECIDE a value (seed `sort:` from the column's own `key:` the moment
  // it's ticked) rather than just copy `el.checked` across. Unlike
  // #updateColumnField, this rebuilds the inspector: checking/unchecking
  // changes whether the sort-key text field is shown on this same column
  // AND whether this column appears at all in the table-level sort
  // dropdown (#sortControlHtml reads sortable columns straight off this
  // same node's `columns` option on every render) -- both are only
  // correct after a fresh build, exactly like #addColumn/#removeColumn
  // already rebuild for the same reason.
  //
  // Tree#guard_sort_requires_sort_url drops a column's `sort:` outright
  // (with a loud error) the moment it sees one without the table's own
  // `sort_url:` present -- so ticking this box while sort_url is still
  // unconfigured used to write a `sort:` the very next preview round-trip
  // stripped straight back out: the normalized workspace came back with
  // `sort` gone, this controller wrote that normalized workspace back, and
  // the checkbox silently reverted to unchecked. The fix is NOT to relax
  // that guard (a design posted from anywhere still has to earn a working
  // sort_url before a column gets to claim one) but to never hand it a
  // tree that fails it in the first place: when the box is ticked and
  // there's no sort_url yet, #_seedSortUrlIfMissing writes a valid default
  // one into the SAME mutator this method already passes to #_updateTree,
  // so the `sort:` and the `sort_url:` land as one tree mutation -- one
  // undo entry, one preview request, nothing for Tree to reject. Unticking
  // never touches sort_url at all, seeded or user-edited, so clearing every
  // sortable column can't lose it either.
  toggleColumnSort(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption
    const index = Number(el.dataset.editorIndex)

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const columns = Array.isArray(current) ? current.map((c) => ({ ...c })) : []
      if (!columns[index]) columns[index] = {}

      if (el.checked) {
        columns[index].sort = columns[index].key || ""
        const withSort = Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
        return this._seedSortUrlIfMissing(withSort, nodeId)
      }

      delete columns[index].sort
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], columns)
    })
    this._renderInspector()
    this._schedulePreview()
  }

  // @return [Object] `tree` unchanged if `nodeId` already carries SOMETHING
  //   under options.sort_url -- valid or not, fully typed or only half
  //   filled in -- since that's the user's own in-progress configuration
  //   and overwriting it would be exactly the kind of silent data loss this
  //   fix exists to prevent. Only a genuinely empty slot (never configured,
  //   or emptied out via #clearSortUrl) gets DEFAULT_SIMPLE_SORT_URL
  //   written in.
  _seedSortUrlIfMissing(tree, nodeId) {
    const current = Tree.getNodeValue(tree, nodeId, ["options", "sort_url"])
    if (current && typeof current === "object") return tree

    return Tree.setNodeValue(tree, nodeId, ["options", "sort_url"], { ...DEFAULT_SIMPLE_SORT_URL })
  }

  // "Clear sort" in editor/inspector.js#sortControlHtml -- drops the whole
  // table-level `sort:` option (as opposed to picking "(unsorted)" in the
  // key dropdown, which only clears the `key` sub-field and leaves a
  // `{ dir: ... }` remnant -- functionally equivalent, since
  // Table::Component#normalize_sort treats a keyless sort: Hash as
  // unsorted too, but this is the tidy version for someone who wants the
  // option gone from the exported ERB entirely). Rebuilds the inspector so
  // the dropdown/direction controls disappear along with the value.
  clearTableSort(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption

    this._updateTree((tree) => Tree.setNodeValue(tree, nodeId, ["options", optionName], undefined))
    this._renderInspector()
    this._schedulePreview()
  }

  // The Simple/Custom pattern buttons in editor/inspector.js#sortUrlControlHtml.
  // A dedicated action, not #applyField, for two reasons: clicking the
  // ALREADY-active-looking button still has to do something (the first
  // click ever, before `options.sort_url` exists at all, looks like it's
  // clicking "Simple" when nothing is set yet), and switching modes seeds
  // sensible defaults (the conventional "sort"/"dir" parameter names, and
  // -- see DEFAULT_SIMPLE_SORT_URL/DEFAULT_PATTERN_SORT_URL's own comment --
  // an already-valid path/pattern) the moment a mode is (re)selected.
  //
  // Those defaults are written into the FIELDS, not left as inert input
  // placeholders nobody actually typed: an empty `path`/`pattern` is
  // exactly what Tree#valid_simple_sort_url?/#valid_pattern_sort_url?
  // reject, so a blank default would fail validation the moment this
  // method's own write reaches the next preview round-trip -- picking
  // "Simple" would silently bounce straight back to "Not configured" with
  // no error a user could connect to what they just clicked, the same
  // class of self-undoing control #toggleColumnSort's own fix (above) had
  // to close for the "Sortable" checkbox.
  //
  // Existing fields from BOTH modes are preserved across the switch
  // (spread first, only `mode` and any missing default overwritten) so
  // bouncing from simple -> pattern -> simple never loses what was typed
  // on either side -- Tree only ever reads the fields belonging to
  // whichever `mode` is currently set, so the other side's leftover keys
  // just ride along inertly until the user switches back to them. A field
  // left over from a PRIOR pick (even an empty string a user cleared by
  // hand) is treated the same as "never set" here (`!next.path`, not
  // `next.path == null`) -- on this control there is no meaningful
  // difference between the two: either way nothing usable is typed there,
  // and defaulting past it is what keeps the freshly-selected mode valid.
  setSortUrlMode(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption
    const mode = el.dataset.editorMode

    this._updateTree((tree) => {
      const current = Tree.getNodeValue(tree, nodeId, ["options", optionName])
      const next = (current && typeof current === "object") ? { ...current } : {}
      next.mode = mode
      if (mode === "simple") {
        if (next.sortParam == null) next.sortParam = DEFAULT_SIMPLE_SORT_URL.sortParam
        if (next.dirParam == null) next.dirParam = DEFAULT_SIMPLE_SORT_URL.dirParam
        if (!next.path) next.path = DEFAULT_SIMPLE_SORT_URL.path
      } else if (!next.pattern) {
        next.pattern = DEFAULT_PATTERN_SORT_URL.pattern
      }
      return Tree.setNodeValue(tree, nodeId, ["options", optionName], next)
    })
    this._renderInspector()
    this._schedulePreview()
  }

  // "Clear" in editor/inspector.js#sortUrlControlHtml -- drops the whole
  // declarative `sort_url:` option, returning the control to its
  // unconfigured "pick a mode" state. Any column still marked `sort:`
  // becomes dangling the moment this lands (Tree#guard_sort_requires_sort_url
  // drops it on the next preview and reports why, surfaced through the
  // usual errors banner) -- this action doesn't cascade that clear itself,
  // matching Tree's own "drop the offending piece, report why" contract
  // rather than silently rewriting columns this control doesn't own.
  clearSortUrl(event) {
    const el = event.currentTarget
    const nodeId = el.dataset.editorNodeId
    const optionName = el.dataset.editorOption

    this._updateTree((tree) => Tree.setNodeValue(tree, nodeId, ["options", optionName], undefined))
    this._renderInspector()
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
  //
  // `decorate` rides along on every call this makes, including #exportAll's
  // own direct use of this method -- harmless there: ErbGenerator (the
  // only field export.js reads, `erb`) has no decoration concept at all
  // and never will (EditorController#preview's own doc), so a decorated
  // `html` field export.js never looks at costs nothing and changes
  // nothing about what gets zipped.
  _fetchPreview(path, signal) {
    return fetch(this.previewUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfTokenValue
      },
      body: JSON.stringify({ path, workspace: this._workspace, decorate: this._guidesEnabled }),
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
    // Guides piggyback on the same two triggers, but not the same call:
    // #_repositionOverlay is O(1) (one selected/hovered node) and stays
    // un-throttled here exactly as it always has; guide recompute is
    // O(number of containers), so scroll -- which can fire many times a
    // second -- goes through #_scheduleGuidesReposition's rAF coalescing
    // instead of calling #_repositionGuides directly the way resize does
    // (a resize is a discrete, low-frequency event with nothing to
    // coalesce). See #_repositionGuides' own doc for the full trigger
    // list, including the two that are NOT wired here (canvas repaint,
    // shown.bs.tab).
    this._frameScrollHandler = () => {
      this._repositionOverlay()
      this._scheduleGuidesReposition()
    }
    this._frameResizeHandler = () => {
      this._repositionOverlay()
      this._repositionGuides()
    }
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
    this._cancelGuidesFrame()
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
      this._stampEmptyContainers(canvasEl)
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
    // Trigger 1 of #_repositionGuides, same reasoning -- every marker/
    // row/column element a guide pointed at is gone with the old subtree.
    // A dedicated call, not folded into #_repositionOverlay above: that
    // method is O(1) (one selected/hovered node), this one is O(number of
    // containers), and the two triggers below (scroll/resize) treat that
    // cost difference very differently (see #_repositionGuides' own doc).
    this._repositionGuides()
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

  // Layout-guide sibling of #_makeCanvasDraggable, run right alongside it
  // on every repaint and for the same reason: a presentation-only stamp
  // over the JUST-painted subtree, wiped along with the rest of it on the
  // next repaint, never read back into the tree, never present in the
  // exported .html.erb. Rows and columns render as real elements with no
  // server-side decoration help at all (see this feature's own task
  // note), but an EMPTY one collapses to 0px -- nothing for its own guide
  // box (#_collectGuideRects) to outline and nothing to aim a drop at --
  // so this gives it editor_canvas.css's decoration-only min-height class
  // first. Walks the tree rather than the DOM (`(node.children || [])`)
  // because "empty" is a tree fact, not a DOM one: a row with only
  // whitespace text nodes, say, would look non-empty to a DOM child-count
  // check but is exactly as empty from the design's own point of view.
  //
  // Second pass, same class, same reasoning, different emptiness test: an
  // empty ROOT-SHARED component (card_group, badge_list, alert, ribbon --
  // drop_target.js#isEmptyRootSharedComponent) collapses exactly as flat as
  // an empty row/column, but "empty" means something different for one of
  // these -- no children array to check, its content lives in `node.slots`
  // instead. Kept as its OWN walk (#_collectEmptyRootSharedNodes) rather
  // than folded into #_collectContainerNodes above: that method's result
  // also feeds #_collectGuideRects, which already finds a root-shared
  // component's own guide rect a completely different way (the
  // `[data-editor-slot-shared]` DOM query, this file's header, "Layout
  // guides") -- merging the two walks would hand #_collectGuideRects a
  // second, redundant rect for the same element, drawing two overlapping
  // guide boxes over one component.
  _stampEmptyContainers(canvasEl) {
    const tree = this._currentTree()

    this._collectContainerNodes(tree, []).forEach((node) => {
      if ((node.children || []).length > 0) return
      const el = canvasEl.querySelector(`[data-editor-node-id="${this._cssEscape(node.id)}"]`)
      if (el) el.classList.add("docs-editor-canvas-empty-container")
    })

    this._collectEmptyRootSharedNodes(tree, []).forEach((node) => {
      const el = canvasEl.querySelector(`[data-editor-node-id="${this._cssEscape(node.id)}"]`)
      if (el) el.classList.add("docs-editor-canvas-empty-container")
    })
  }

  // See this file's header, "Drag-only growth: something to aim at" --
  // called once from #paletteDragStart/#_onFrameDragStart, never from a
  // per-dragover-tick handler. Independent height/width classes (rather
  // than one class covering both) so an element only grows in the
  // dimension it was actually too small in.
  _growSmallDropTargets() {
    if (!this._frameDoc) return
    const canvasEl = this._frameDoc.getElementById("tabler-ui-editor-canvas")
    if (!canvasEl) return

    // `:not([aria-hidden="true"])` excludes the empty-slot PLACEHOLDER
    // Renderer synthesizes (#editor_slot_placeholder) -- the exact same
    // element #_collectGuideRects' own `seenSlots` dedup already has to
    // work around, for the exact same reason (that method's own comment):
    // it deliberately carries the SAME data-editor-node-id/data-editor-slot
    // pair as the real wrapper around it, so a naive "every stamped
    // element" query matches an empty slot TWICE. There, the fix is to
    // keep only the first (real) match; here, the placeholder has to be
    // excluded outright rather than merely deduped, because growing it is
    // actively harmful, not just redundant: it is never reachable by a
    // pointer in the first place (0x0 and aria-hidden, so elementFromPoint
    // can never land on it), but forcing it to DRAG_GROW_MIN_SIZE tall
    // still inserts that much real, visible empty space into its parent
    // -- confirmed live against the running editor: an empty card's own
    // `.card-body` measured 32px before this exclusion was added, and
    // grew to 64px during a drag, entirely from its own invisible
    // placeholder child being forced tall, not from anything a user could
    // ever have meant to aim at.
    canvasEl.querySelectorAll('[data-editor-node-id]:not([aria-hidden="true"])').forEach((el) => {
      const rect = el.getBoundingClientRect()
      if (rect.height < DRAG_GROW_MIN_SIZE) el.classList.add("docs-editor-canvas-drag-grow-height")
      if (rect.width < DRAG_GROW_MIN_SIZE) el.classList.add("docs-editor-canvas-drag-grow-width")
    })

    // The growth just applied is a real layout change -- every guide rect
    // already on screen was measured before it ran, so it's now off by
    // however much its own container (or an ancestor's) just grew. One
    // reposition catches every guide up in a single pass; nothing else for
    // the rest of the drag recomputes them again (this file's header).
    this._repositionGuides()
  }

  // Counterpart of #_growSmallDropTargets, called from #_endDrag. Explicit
  // rather than left to the next #_paintCanvas's innerHTML replacement to
  // clean up incidentally -- see this file's header for why that repaint
  // is not a reliable enough backstop on its own.
  _shrinkGrownDropTargets() {
    if (!this._frameDoc) return
    const canvasEl = this._frameDoc.getElementById("tabler-ui-editor-canvas")
    if (!canvasEl) return
    canvasEl.querySelectorAll(".docs-editor-canvas-drag-grow-height, .docs-editor-canvas-drag-grow-width").forEach((el) => {
      el.classList.remove("docs-editor-canvas-drag-grow-height", "docs-editor-canvas-drag-grow-width")
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

    // See #paletteDragStart's own comment on this same call -- identical
    // reasoning, just the other of the two places a drag can start.
    this._growSmallDropTargets()

    // See #paletteDragStart's own comment on this same block -- identical
    // reasoning (guides stay drawn and merely mute), just the other of the
    // two documents a drag can start in.
    if (this._overlay) {
      this._overlay.clearSelection()
      this._overlay.clearToolbar()
      this._overlay.setGuidesMuted(true)
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

    // #_hitTestDragTarget alone only ever matches a real stamped element --
    // over the new gutter padding (or any other dead space around a
    // root-level child) it finds nothing, so #_hitTestRootFallback is tried
    // second, never instead: a real element under the pointer always wins.
    // See that method's own header for why this is a root-relative
    // before/after/beside resolution now, not always a trailing append.
    const hit = this._hitTestDragTarget(event.clientX, event.clientY) || this._hitTestRootFallback(event.clientX, event.clientY)
    const descriptor = resolveDropTarget({
      tree: this._currentTree(),
      schema: this._schema,
      hoveredNodeId: hit ? hit.id : null,
      hoveredRect: hit ? hit.rect : null,
      hoveredSlotName: hit ? hit.slotName : null,
      pointerX: event.clientX,
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

  // The same "elementFromPoint + closest [data-editor-node-id]" lookup
  // DnD.hitTestStamped already does (see that function's own header for
  // why it stays its own small copy rather than a shared helper --
  // #_updateHoverFromPoint above is a second, independent copy of the
  // same two lines for exactly that reason) -- kept as a THIRD small copy
  // here, rather than widening hitTestStamped's own {id, rect} return
  // shape, because this call site needs one more thing off the SAME
  // matched element: `data-editor-slot`, present only on a decorated
  // PRECISE slot's own dedicated wrapper (Renderer#stamp_slot_marker),
  // naming which slot of the hovered component this exact element is --
  // see drop_target.js's own header on `hoveredSlotName` for what that
  // unlocks (the middle band resolving straight into that slot instead of
  // the cursor-anchored chip menu). Deliberately reads `data-editor-slot`
  // only, never `data-editor-slot-shared` (Renderer#stamp_shared_slot's
  // different attribute for a ROOT_SHARED slot with no wrapper of its
  // own) -- leaving that one unread is what keeps a root-shared component
  // (alert, avatar, badge_list, card_group, ribbon) resolving through the
  // chip path exactly as before.
  //
  // @return {id, rect, slotName} for the stamped element under the point,
  //   or null. `slotName` is null whenever the matched element carries no
  //   `data-editor-slot` -- guides off (the attribute doesn't exist in the
  //   DOM at all then, Renderer's own `if @decorate` gate), the matched
  //   element is a component's plain root, or it's some other kind
  //   entirely (row/column/fragment/leaf).
  _hitTestDragTarget(x, y) {
    if (!this._frameDoc || !this._frameDoc.elementFromPoint) return null
    const el = this._frameDoc.elementFromPoint(x, y)
    const target = el && el.closest ? el.closest("[data-editor-node-id]") : null
    if (!target) return null
    return {
      id: target.getAttribute("data-editor-node-id"),
      rect: target.getBoundingClientRect(),
      slotName: target.getAttribute("data-editor-slot")
    }
  }

  // #_hitTestDragTarget's own fallback, tried only when it found nothing --
  // the pointer is over the new gutter padding around the design
  // (editor_canvas.css's own #tabler-ui-editor-canvas rule), a gap between
  // two root-level siblings, or dead space below a design shorter than the
  // frame itself. Before this existed, "no stamped element under the
  // pointer" always fell through to #resolveAgainstRoot's plain append --
  // right for the space below the last component, but wrong everywhere
  // else: hovering the new top gutter, plainly aiming ABOVE the first
  // component, still landed the drop at the very end. This resolves the
  // pointer against whichever ROOT-LEVEL child it is vertically nearest to
  // instead, and hands that back in exactly the {id, rect, slotName} shape
  // #_hitTestDragTarget already returns for a real hit -- #_onFrameDragOver
  // cannot tell the difference, so every existing rule for a real hit
  // (edgeBandFor's four-edge test, the vertical three-band split, the
  // left/right "join this row" / "wrap into a new one" cases) already
  // applies unchanged: above the nearest child resolves to "before" it,
  // below to "after", and beside it to whatever those same horizontal
  // rules already do for a root-level node -- see drop_target.js's own
  // header, "Four edges, one rule". Only root-level children are ever
  // candidates here (this reads `tree.children`, not the DOM subtree), so
  // a gap INSIDE some other container (say, between two rows nested three
  // levels down) is not this method's concern -- that space sits inside an
  // element #_hitTestDragTarget already matches directly.
  //
  // @return the same {id, rect, slotName} shape as #_hitTestDragTarget, or
  //   null when the tree is empty or unavailable, or open, or none of its
  //   root children still have a stamped element on screen -- the caller
  //   falls through to #resolveAgainstRoot's plain append in that case,
  //   same as before this method existed.
  _hitTestRootFallback(x, y) {
    const tree = this._currentTree()
    if (!tree || !this._frameDoc) return null
    const children = Array.isArray(tree.children) ? tree.children : []

    let nearest = null
    let nearestDistance = Infinity
    children.forEach((child) => {
      const el = this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(child.id)}"]`)
      if (!el) return
      const rect = el.getBoundingClientRect()
      // 0 when the pointer's own Y already falls within this child's own
      // vertical span (it is "beside" this child, not above or below it) --
      // the same three-way split #resolveAgainstElement's band logic is
      // about to re-derive from `rect` and `y` anyway, computed here only
      // well enough to pick WHICH child to hand it, not to duplicate that
      // logic.
      const distance = y < rect.top ? rect.top - y : y > rect.bottom ? y - rect.bottom : 0
      if (distance < nearestDistance) {
        nearestDistance = distance
        nearest = { id: child.id, rect, slotName: null }
      }
    })
    return nearest
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
      this._overlay.clearWrapOutline()
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
  // chip -- same {parentId, container, index} shape) describes. "wrap" and
  // "column" are each peeled off first into their own compound-mutation
  // helper (#_applyWrapDrop / #_applyColumnInsertDrop) -- both build a
  // brand-new column around the dragged node, just around a brand-new row
  // vs. an existing one, so neither fits the plain insertAt/moveNodeTo
  // shape every other position uses. What's left is two branches on
  // `this._dragState.sourceNodeId`: null means this is a palette drag
  // building a brand-new node (#_buildNewNode + Tree.insertAt, exactly what
  // #_onFrameDrop always did before canvas-node dragging existed); set
  // means this is an existing node being moved (Tree.moveNodeTo).
  // Deliberately does not gate on `target.valid`: validity is advisory only
  // (drop_target.js's own header) -- an "invalid" target is still handed to
  // Tree.moveNodeTo/Tree.insertAt exactly like any other edit. For
  // moveNodeTo specifically this is more than "advisory" in practice:
  // dropping into a node's own descendant is already a safe no-op at the
  // data layer (tree.js's own header on #moveNodeTo) regardless of what
  // this file thinks `valid` should say, so there is nothing here that
  // NEEDS gating for correctness -- only the ghost/chip's appearance
  // depends on it.
  _applyDrop(target) {
    if (!target || !target.parentId) return

    if (target.position === "wrap") {
      this._applyWrapDrop(target)
      this._schedulePreview()
      return
    }

    if (target.position === "column") {
      this._applyColumnInsertDrop(target)
      this._schedulePreview()
      return
    }

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

  // The "wrap" branch of #_applyDrop -- builds the {newNode}/{moveId}
  // payload tree.js#wrapInRow's own contract expects (see that function's
  // header) from the SAME sourceNodeId/kind/component split #_applyDrop's
  // other branch already makes, then hands it, `target`'s own
  // wrapTargetId/wrapSide/columnSpan (all resolved already by
  // drop_target.js#resolveHorizontalEdge), straight through.
  _applyWrapDrop(target) {
    const payload = this._dragState.sourceNodeId
      ? { moveId: this._dragState.sourceNodeId }
      : { newNode: this._buildNewNode(this._dragState.kind, this._dragState.component) }
    if (!payload.moveId && !payload.newNode) return

    this._updateTree((tree) => Tree.wrapInRow(tree, target.wrapTargetId, target.wrapSide, payload, target.columnSpan))
  }

  // The "column" branch of #_applyDrop -- #_applyWrapDrop's sibling for
  // joining an EXISTING row instead of building a brand-new one (see
  // drop_target.js's header, "Four edges, one rule", case 1, for when this
  // resolves over #_applyWrapDrop's case 2). Builds the exact same
  // {newNode}/{moveId} payload shape tree.js#insertColumnBeside expects --
  // and that #_applyWrapDrop already builds the same way one line up, so
  // this is genuinely the same split, not a near-miss copy of it -- then
  // hands it `target`'s own columnTargetId/columnSide/columnSpan (all
  // resolved already by drop_target.js#resolveHorizontalEdge) straight
  // through, plus this._schema so tree.js#insertColumnBeside can rebalance
  // the joined row's columns back to equal widths when they were still
  // uniform (see that function's own header).
  _applyColumnInsertDrop(target) {
    const payload = this._dragState.sourceNodeId
      ? { moveId: this._dragState.sourceNodeId }
      : { newNode: this._buildNewNode(this._dragState.kind, this._dragState.component) }
    if (!payload.moveId && !payload.newNode) return

    this._updateTree((tree) => Tree.insertColumnBeside(tree, target.columnTargetId, target.columnSide, payload, target.columnSpan, this._schema))
  }

  // Renders the ghost box + insertion line, the wrap chrome, OR the chip
  // menu, for the drop `descriptor` resolved this tick -- exactly one of
  // the three is ever showing at once, so each branch below clears the
  // others' chrome before (or instead of) drawing its own. Six cases, in
  // the order checked:
  //
  //   1. no descriptor at all (drag left the frame, #_onFrameDragLeave) --
  //      clear everything.
  //   2. `position: "chips"` -- delegate to #_paintChips; no ghost/
  //      insertion line for this tick.
  //   3. `position: "wrap"` -- a bigger change than a plain insert (it
  //      builds a whole new row), so it gets its own, visually distinct
  //      chrome rather than reusing the plain ghost's look: a wrap
  //      outline over the FULL hovered element (drop_target.js's own
  //      `.docs-editor-canvas-box-wrap` -- everything currently there is
  //      about to become one half of a new row) plus a ghost sized to
  //      exactly HALF that element's width, on the side the dragged node
  //      will actually land, in the wrap's own colour (setGhost's `wrap`
  //      flag) so it doesn't read as an ordinary "into" ghost.
  //   4. `position: "into"` -- landing INSIDE the hovered element itself
  //      (a row/column/fragment taking children directly), so the ghost is
  //      drawn as that element's own full rect rather than a sliver beside
  //      it, and there is no edge to draw an insertion line against.
  //   5. `position: "before"/"after"/"column"` (descriptor.anchorRect set)
  //      -- insertion line flush with the resolved edge, ghost sized off
  //      the hovered element's own cross-dimension, sitting just outside it
  //      on the correct side. `descriptor.lineOrientation` picks which way:
  //      "horizontal" (a top/bottom edge) draws the ORIGINAL full-width bar
  //      above/below the element, same as before this feature; "vertical"
  //      (a left/right edge, drop_target.js's horizontal bands) draws a
  //      full-height bar beside it instead, with the ghost a narrow sliver
  //      of the SAME thickness (ROOT_GHOST_HEIGHT) sitting left or right
  //      rather than above or below -- so a left/right insertion reads as a
  //      vertical line on that edge, never the horizontal one. "column" is
  //      deliberately NOT given its own branch here, unlike "wrap": it is a
  //      structural change (a new column joins an existing row) but a small
  //      one, and the plain vertical insertion line this branch already
  //      draws for an ordinary left/right "before"/"after" is exactly the
  //      right chrome for it too -- a thin line at the column boundary, not
  //      a whole-element outline. That is also the distinction this file's
  //      task cares about: a sibling-column insert must read as visibly
  //      DIFFERENT from a wrap's box-around-the-whole-element chrome
  //      (case 3 above), which it does simply by falling through to this
  //      case instead of case 3.
  //   6. `position: "append"` with no anchorRect -- reached only for a
  //      genuinely EMPTY tree now (#_hitTestRootFallback resolves every
  //      other "no stamped element under the pointer" case -- gutter,
  //      inter-sibling gap, dead space below a short design -- against the
  //      nearest root-level child instead, landing in one of the branches
  //      above with a real anchorRect). No insertion line, ghost sized off
  //      the canvas element itself, at ROOT_GHOST_HEIGHT (drop_target.js's
  //      own constant, so the two never drift apart).
  _paintDragGhost(descriptor, event) {
    if (!this._overlay) return
    if (!descriptor) {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearChips()
      this._overlay.clearWrapOutline()
      return
    }

    if (descriptor.position === "chips") {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearWrapOutline()
      this._paintChips(descriptor, event)
      return
    }
    this._overlay.clearChips()

    if (descriptor.position === "wrap") {
      const anchor = descriptor.anchorRect
      this._overlay.setInsertionLine(descriptor.insertionRect, descriptor.lineOrientation)
      this._overlay.setWrapOutline(anchor, "New row")
      const halfWidth = anchor.width / 2
      const left = descriptor.wrapSide === "before" ? anchor.left : anchor.left + halfWidth
      this._overlay.setGhost(rectOf(left, anchor.top, halfWidth, anchor.height), this._dragState.label, descriptor.valid, true)
      return
    }
    this._overlay.clearWrapOutline()

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
      this._overlay.setInsertionLine(descriptor.insertionRect, descriptor.lineOrientation)

      if (descriptor.lineOrientation === "vertical") {
        const width = Math.max(20, Math.min(ROOT_GHOST_HEIGHT, anchor.width))
        const left = descriptor.edge === "left" ? anchor.left - width : anchor.right
        this._overlay.setGhost(rectOf(left, anchor.top, width, anchor.height), this._dragState.label, descriptor.valid)
      } else {
        const height = Math.max(20, Math.min(ROOT_GHOST_HEIGHT, anchor.height))
        const top = descriptor.position === "before" ? anchor.top - height : anchor.bottom
        this._overlay.setGhost(rectOf(anchor.left, top, anchor.width, height), this._dragState.label, descriptor.valid)
      }
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
    // See this file's header, "Drag-only growth" -- undoes
    // #_growSmallDropTargets explicitly, on both a successful drop and a
    // cancelled drag, rather than counting on the next repaint to happen
    // to wipe it.
    this._shrinkGrownDropTargets()
    if (this._overlay) {
      this._overlay.clearGhost()
      this._overlay.clearInsertionLine()
      this._overlay.clearChips()
      this._overlay.clearWrapOutline()
      // Un-mute back to the guides' normal appearance -- #paletteDragStart/
      // #_onFrameDragStart's own comment. #_paintCanvas below (now that
      // this._dragState is cleared) repaints the canvas and, at its tail,
      // recomputes the guide set proper against whatever the drop (or its
      // absence, for a cancelled drag) actually left in the tree -- this
      // call only restores the LOOK of whatever is still on screen from a
      // moment ago, it does not itself redraw geometry.
      this._overlay.setGuidesMuted(false)
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
    this._repositionGuides()
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

  // === Layout guides ==========================================================
  //
  // Recomputes and redraws the full guide set -- ghost outlines over every
  // server-decorated slot marker plus every row/column tree node -- from
  // scratch. "From scratch" is safe to say here even though it sounds like
  // the rebuild-every-time pattern this feature's own task note warns
  // against: the EXPENSIVE part of that pattern is DOM churn (destroying
  // and recreating elements), and overlay.js#setGuides is what avoids
  // that, by diffing this method's rect list against the boxes already on
  // screen instead of rebuilding them. Recomputing the *list itself* on
  // every trigger is unavoidable and cheap relative to that -- there is no
  // stale-but-still-correct subset of "every container in the design" to
  // reuse the way a diffed DOM node can be reused.
  //
  // Four triggers share this method, matching #_repositionOverlay's own
  // four exactly (that method's own doc has the full reasoning for each):
  // the tail of #_paintCanvas (direct call), "scroll" on the frame
  // document (via #_scheduleGuidesReposition's rAF coalescing -- see that
  // method's own doc for why scroll alone is throttled here while resize
  // and repaint are not), "resize" on the frame's own window (direct
  // call), and Bootstrap's shown.bs.tab on the Preview tab's anchor
  // (#repositionOverlay, the public Stimulus-action wrapper both this and
  // #_repositionOverlay share).
  //
  // Guarded on #_guidesEnabled alone (an explicit off means "show
  // nothing", not "show whatever was last computed") -- NOT on
  // this._dragState. Guides deliberately stay live through a drag (see
  // #paletteDragStart's own doc for why the old "suppress for the whole
  // drag" behaviour was wrong), and this is the method that keeps them
  // correct while one is in progress: #_paintCanvas -- the trigger below
  // that would otherwise recompute the rect list from a changed DOM -- is
  // itself a no-op for as long as this._dragState is set, so the only
  // triggers that can actually reach this method mid-drag are scroll (via
  // #_scheduleGuidesReposition) and resize/shown.bs.tab (direct calls,
  // just below). All three re-measure the SAME already-correct elements
  // with getBoundingClientRect() -- nothing about the tree or the canvas
  // subtree changed, only the viewport-relative position of things already
  // on screen -- so letting them run mid-drag is a reposition, never the
  // per-dragover-tick full recompute this feature's own task note warns
  // against (dragover itself, #_onFrameDragOver, never calls this method
  // at all).
  _repositionGuides() {
    if (!this._overlay) return
    if (!this._guidesEnabled) {
      this._overlay.clearGuides()
      return
    }
    this._overlay.setGuides(this._collectGuideRects())
  }

  // Coalesces scroll-triggered guide recomputes into at most one per
  // animation frame -- unlike #_repositionOverlay (O(1), left un-throttled
  // even on scroll), a full guide recompute is O(number of containers) in
  // the design, and a mouse wheel or trackpad can fire "scroll" many times
  // between two frames. Mirrors #_onFramePointerMove's own rAF-coalescing
  // shape (and #_hoverRafId/#_cancelHoverFrame) for the same reason: only
  // the LATEST state matters once a frame's worth of scroll events have
  // all landed, so nothing is lost by dropping the intermediate ones.
  _scheduleGuidesReposition() {
    if (this._guidesRafId != null) return // already scheduled for this frame
    const view = this._frameDoc && this._frameDoc.defaultView
    if (!view) {
      this._repositionGuides()
      return
    }
    this._guidesRafId = view.requestAnimationFrame(() => {
      this._guidesRafId = null
      this._repositionGuides()
    })
  }

  _cancelGuidesFrame() {
    if (this._guidesRafId != null && this._frameDoc && this._frameDoc.defaultView) {
      this._frameDoc.defaultView.cancelAnimationFrame(this._guidesRafId)
    }
    this._guidesRafId = null
  }

  // Builds this tick's full rect list -- see #_repositionGuides' own doc
  // for when this runs. Two sources, per this feature's own task note:
  //
  //   1. Server markers -- every [data-editor-slot] (the PRECISE case: a
  //      slot with its own dedicated wrapper part, labelled with the slot
  //      name) and every [data-editor-slot-shared] (the COARSE case: a
  //      component whose slot content renders straight into its own root
  //      with no wrapper of its own -- alert, avatar, badge_list,
  //      card_group, ribbon -- labelled from every shared slot name
  //      together, see the loop below for why). Both only ever exist in
  //      the DOM at all when this preview was rendered with `decorate:
  //      true` (Renderer's own gate) -- if a stale, undecorated response
  //      is still painted when this runs (the toggle flipped on but the
  //      new preview hasn't landed yet), these two queries simply find
  //      nothing, and the guide set catches up the moment #_paintCanvas
  //      repaints with the decorated response.
  //   2. The tree -- every row/column node, resolved to its own stamped
  //      element and labelled with its own kind. These need no server
  //      help to exist as real elements (see this feature's own task
  //      note), so this walks `this._currentTree()` directly rather than
  //      querying for another server-side marker.
  //
  // Each rect's `id` is stable across recomputes of the SAME tree/DOM
  // state (built from the owning node's id, never from array position or
  // insertion order), which is exactly what overlay.js#setGuides needs to
  // diff correctly rather than tearing down and rebuilding every box on
  // every scroll tick.
  _collectGuideRects() {
    if (!this._frameDoc) return []
    const rects = []

    // The empty-slot placeholder Renderer synthesizes
    // (#editor_slot_placeholder) deliberately carries the SAME
    // data-editor-slot/data-editor-node-id pair as the real wrapper
    // around it (see that method's own comment: "so the client can
    // identify a placeholder on its own terms") -- which means a single
    // empty slot matches this query TWICE, wrapper then placeholder, in
    // that document order. Only the first (the wrapper -- the element
    // that actually has real size, via its own component-CSS padding)
    // is wanted here; the placeholder is an empty, aria-hidden child sat
    // inside it with no size of its own to usefully outline. `seenSlots`
    // keeps only that first match per id.
    const seenSlots = new Set()
    this._frameDoc.querySelectorAll("[data-editor-slot]").forEach((el) => {
      const nodeId = el.getAttribute("data-editor-node-id")
      const slot = el.getAttribute("data-editor-slot")
      const id = `slot:${nodeId}:${slot}`
      if (seenSlots.has(id)) return
      seenSlots.add(id)
      rects.push(this._guideRectFor(el, id, slot))
    })

    // The coarse case never has a placeholder to collide with (Renderer
    // never synthesizes one for a ROOT_SHARED slot -- its region already
    // IS the component root, which always renders regardless), so no
    // dedup is needed here. Labelled by joining every shared slot name
    // with " + " rather than picking just one: SlotParts maps at most one
    // slot to ROOT_SHARED per component today, but the attribute itself
    // is already comma-joined for the case where a future component maps
    // more than one (Renderer#stamp_shared_slot's own doc), and "+" reads
    // unambiguously as "this one guide stands in for all of these" --
    // distinct from the plain single-word label a precise slot gets,
    // which is the whole point: this element is the coarser of the two
    // cases, and its label should look like it.
    this._frameDoc.querySelectorAll("[data-editor-slot-shared]").forEach((el) => {
      const nodeId = el.getAttribute("data-editor-node-id")
      const names = el.getAttribute("data-editor-slot-shared").split(",")
      rects.push(this._guideRectFor(el, `slot-shared:${nodeId}`, names.join(" + ")))
    })

    this._collectContainerNodes(this._currentTree(), []).forEach((node) => {
      const el = this._frameDoc.querySelector(`[data-editor-node-id="${this._cssEscape(node.id)}"]`)
      if (el) rects.push(this._guideRectFor(el, `container:${node.id}`, node.kind))
    })

    return rects
  }

  _guideRectFor(el, id, label) {
    const rect = el.getBoundingClientRect()
    return { id, label, left: rect.left, top: rect.top, width: rect.width, height: rect.height }
  }

  // Every row/column node anywhere in `node`, walking the same set of
  // child arrays Tree.js's own internal traversal does -- `children`
  // (fragment/row/column), each value of `slots` (a slot-style
  // component's own content), and `items` (a builder-style component or a
  // builder_item with block: :items) -- so a row or column nested inside
  // a slot or a builder item's own children is found too, not just ones
  // that hang directly off the root. Not itself exported from tree.js
  // (that module's own `childArrays` is private to it), so this is a
  // second, small copy of the same shape rather than a new export earned
  // by exactly one caller.
  _collectContainerNodes(node, acc) {
    if (!node) return acc
    if (node.kind === "row" || node.kind === "column") acc.push(node)
    if (Array.isArray(node.children)) node.children.forEach((child) => this._collectContainerNodes(child, acc))
    if (node.slots && typeof node.slots === "object") {
      Object.values(node.slots).forEach((arr) => (arr || []).forEach((child) => this._collectContainerNodes(child, acc)))
    }
    if (Array.isArray(node.items)) node.items.forEach((item) => this._collectContainerNodes(item, acc))
    return acc
  }

  // #_collectContainerNodes' sibling for #_stampEmptyContainers' second
  // pass (that method's own doc explains why this is a separate walk
  // rather than folded into the one above) -- same traversal shape
  // (children/slots/items), same "keep walking past a match" behaviour (an
  // empty card_group nested inside a row still needs the row found too, if
  // it's ALSO empty, and vice versa), just a different per-node test:
  // drop_target.js#isEmptyRootSharedComponent instead of `node.kind ===
  // "row" || "column"`.
  _collectEmptyRootSharedNodes(node, acc) {
    if (!node) return acc
    if (isEmptyRootSharedComponent(node)) acc.push(node)
    if (Array.isArray(node.children)) node.children.forEach((child) => this._collectEmptyRootSharedNodes(child, acc))
    if (node.slots && typeof node.slots === "object") {
      Object.values(node.slots).forEach((arr) => (arr || []).forEach((child) => this._collectEmptyRootSharedNodes(child, acc)))
    }
    if (Array.isArray(node.items)) node.items.forEach((item) => this._collectEmptyRootSharedNodes(item, acc))
    return acc
  }

  // The toolbar's "Layout guides" switch (editor/show.html.erb) --
  // decoration is server-side (Renderer's `decorate:`), so flipping this
  // can't just redraw the existing overlay the way every other guides
  // method here does: it has to re-request the preview with the new flag.
  // Turning guides OFF also clears whatever is on screen immediately
  // rather than waiting for that round trip -- leaving stale guides up
  // for the length of a network request would read as the toggle having
  // done nothing. Turning guides ON has no equivalent eager step: there is
  // no decorated markup to measure until the new response lands and
  // #_paintCanvas repaints, at which point its own #_repositionGuides call
  // picks it up same as any other repaint.
  toggleGuides(event) {
    this._guidesEnabled = event.currentTarget.checked
    this._saveGuidesEnabled(this._guidesEnabled)
    if (!this._guidesEnabled && this._overlay) this._overlay.clearGuides()
    this._schedulePreview(true)
  }

  // @return {Boolean} true (guides on) for both "the key was never
  // written" and a genuinely corrupt value -- see editor/workspace.js's
  // own header for why this reads/writes tabler-ui-docs-editor:guides
  // directly rather than through a loadWorkspace-shaped helper there: a
  // single boolean has no shape worth one. Never throws -- a
  // localStorage read can fail (private browsing, a disabled/full store)
  // exactly like editor/workspace.js#loadWorkspace's own can, and a
  // failure here should fall back to the same default an absent key gets,
  // not take the whole controller down before #connect finishes.
  _loadGuidesEnabled() {
    try {
      const raw = localStorage.getItem(Workspace.GUIDES_KEY)
      return raw === null ? true : raw === "true"
    } catch (e) {
      return true
    }
  }

  // Counterpart of #_loadGuidesEnabled. DOES report a failure (rather than
  // swallowing it the way the loader's catch above does) -- same
  // reasoning as editor/workspace.js#saveWorkspace's own header: a write
  // failure the user never hears about means the toggle they just clicked
  // silently won't survive a reload.
  _saveGuidesEnabled(enabled) {
    try {
      localStorage.setItem(Workspace.GUIDES_KEY, enabled ? "true" : "false")
    } catch (e) {
      this._renderErrors([`could not save the layout-guides setting: ${e.message}`])
    }
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
