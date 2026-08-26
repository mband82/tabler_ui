// Native HTML5 drag-and-drop plumbing for "drag a palette item, or an
// existing canvas node, onto the canvas" -- purely mechanical
// event-listener wiring and the two DOM primitives (a hit test, a
// cursor-following drag image) that wiring needs. No tree knowledge
// (that's editor/drop_target.js), no controller state
// (editor_controller.js owns `_dragState` and every tree mutation -- see
// its own header, "The lock: _dragState"). Every function here either
// attaches/detaches a fixed set of listeners and returns a detach
// function, or is a stateless DOM query -- nothing in this module is kept
// across calls.
//
// ## SortableJS can't do this
//
// editor_sortable_controller.js drives the Structure and Explorer panes,
// and stays exactly as it is -- it depends on drag and drop start and end
// inside the SAME document. A drag that starts on a palette item (the
// parent editor page) and ends over the design (a separate document
// inside a same-origin <iframe>) crosses a document boundary SortableJS
// was never built to follow. The browser's native drag-and-drop protocol
// has no such restriction -- dragstart/dragover/drop/dragend all fire
// correctly across that boundary -- so this reimplements just the handful
// of native events crossing it requires.
//
// ## Two documents, one JS realm
//
// dragover, dragenter, dragleave and drop are TARGET-side events: they
// fire whichever document the pointer is currently over, so once a drag
// enters the preview <iframe> they land on the FRAME document, not the
// parent page. dragstart is SOURCE-side. So, less obviously, is dragend:
// despite the pointer having spent the whole drag inside the guest
// frame's geometry, `dragend` is dispatched back on the exact element
// `dragstart` fired on and bubbles there. (MDN is explicit about this:
// "This event is fired on the source of the drag, not the target(s).")
//
// Which document that is depends on where the drag STARTED, not where it
// travelled -- two cases, both real in this editor:
//
//   * A palette item (editor_controller.js#paletteDragStart) lives in the
//     PARENT document, so its dragend fires there too, wired as a plain
//     Stimulus `dragend->...#paletteDragEnd` action alongside the
//     existing `click`/`dragstart` ones (editor/palette.js). An element in
//     the parent document is never torn down by a preview repaint the way
//     something inside the frame's own canvas subtree can be, so listening
//     for it there means it is genuinely guaranteed to fire exactly once
//     per drag, success or failure -- Escape, dropping outside the browser
//     window, all of it.
//   * An existing canvas node (editor_controller.js#_onFrameDragStart)
//     lives IN the frame document, so its dragend fires there instead --
//     wired as a plain frame-doc listener alongside click/dblclick/input/
//     etc. (registered in #_onFrameLoad, torn down in
//     #_detachFrameListeners, same as every other frame-doc listener that
//     controller owns), not through this module's #attachFrameDropTarget
//     (that function's four listeners all need the "preventDefault on
//     every tick" dance described below; dragend needs no such thing --
//     its default action is nothing worth preventing).
//
// Either way, #_endDrag is idempotent, so a controller that happens to
// wire both paths never has to worry about which one actually fired for a
// given drag -- see that method's own header.
//
// Both documents share one JS realm (no postMessage, no origin boundary --
// the frame is same-origin by construction, EditorController#frame), so
// the drag's payload (which palette item, which node kind) is carried in
// controller state rather than read back out of `dataTransfer` -- see
// editor_controller.js's own header for why: `getData()` is unreadable
// during `dragover` in most browsers, only becoming readable on `drop`.
// `dataTransfer.setData` is still called at dragstart -- Firefox refuses
// to start a drag at all without it -- its value is simply never read back.

// --- drag source (palette item, or an existing canvas node) -----------

// Wires dragstart/dragend on one palette item element. Called once per
// item at render time would mean re-wiring on every palette rebuild;
// instead editor_controller.js binds these the same way it binds `click`
// -- as Stimulus data-action entries on the item's own markup
// (editor/palette.js, editor/show.html.erb) -- so this module's job is
// smaller than it might look: it owns only the two DOM primitives those
// action methods need, not the listener wiring itself. A canvas-node drag
// (editor_controller.js#_onFrameDragStart) wires its own dragstart/dragend
// directly on the frame document instead (see this file's header), but
// calls the very same #paintDragImage below -- the primitive itself has
// no idea which of the two kicked it off, only the document its own event
// fired in.

// Paints the small chip dataTransfer.setDragImage follows under the
// cursor for the rest of the drag. Must live in the document `dragstart`
// fired in -- `event.target.ownerDocument`, never an assumed `document`,
// since that's the only document guaranteed to still be attached when
// this runs (the parent page for a palette drag, the frame document for a
// canvas-node drag). Positioned on-screen but far off the visible
// area (`position: fixed; top/left: -1000px`) rather than `display: none`
// -- an undisplayed element has nothing to rasterize, and Chrome/Safari
// silently fall back to the default drag ghost if setDragImage is handed
// one. Removed on a double requestAnimationFrame: the browser snapshots
// the element's current paint the first time it actually needs it, which
// on most engines is not synchronously within this call -- removing it
// one frame (or even zero frames) too early ships a blank drag image.
export function paintDragImage(event, label) {
  const doc = event.target && event.target.ownerDocument
  if (!doc || !doc.body || !event.dataTransfer || !event.dataTransfer.setDragImage) return

  const chip = doc.createElement("div")
  chip.className = "docs-editor-drag-chip"
  chip.textContent = label || ""
  chip.style.position = "fixed"
  chip.style.top = "-1000px"
  chip.style.left = "-1000px"
  doc.body.appendChild(chip)
  event.dataTransfer.setDragImage(chip, 12, 12)

  const view = doc.defaultView
  if (!view || !view.requestAnimationFrame) {
    chip.remove()
    return
  }
  view.requestAnimationFrame(() => view.requestAnimationFrame(() => chip.remove()))
}

// --- frame (target) side ------------------------------------------------

// Wires the four target-side listeners on the frame document -- attached
// from editor_controller.js#_onFrameLoad and torn down from
// #_detachFrameListeners, exactly like every other frame-document listener
// that controller already owns (click, dblclick, pointermove, ...). Returns
// a single detach function so the controller has one thing to call, not
// four.
//
// `onDragOver`/`onDrop` receive the raw event (they need clientX/clientY
// and, for onDragOver, dataTransfer.dropEffect) -- resolving it into a
// drop-target descriptor is editor_controller.js's job (it owns the tree
// and schema drop_target.js's resolver needs), not this module's.
//
// `onLeave` fires only for the single "pointer left the frame document
// entirely" signal, not for every dragenter/dragleave pair crossing an
// interior element boundary -- see the `relatedTarget` check below, which
// mirrors #_onFramePointerOut's identical reasoning for the hover box:
// `relatedTarget` is the element the pointer is entering, and is null
// exactly when nothing in this document is being entered, i.e. the drag
// has left it altogether (out through the iframe's own edge, or the
// browser released it outside the window).
export function attachFrameDropTarget(doc, { onDragOver, onDrop, onLeave }) {
  // dragover's default action is "refuse this drop" -- preventDefault()
  // has to run on EVERY tick, unconditionally, or `drop` never fires at
  // all. dragenter needs the same treatment for the same reason (some
  // browsers, notably Firefox, use dragenter rather than the first
  // dragover tick to decide whether a drop zone accepts the drag).
  const dragEnterHandler = (event) => event.preventDefault()

  const dragOverHandler = (event) => {
    event.preventDefault()
    onDragOver(event)
  }

  const dragLeaveHandler = (event) => {
    if (event.relatedTarget) return
    onLeave(event)
  }

  const dropHandler = (event) => {
    event.preventDefault()
    onDrop(event)
  }

  doc.addEventListener("dragenter", dragEnterHandler)
  doc.addEventListener("dragover", dragOverHandler)
  doc.addEventListener("dragleave", dragLeaveHandler)
  doc.addEventListener("drop", dropHandler)

  return function detach() {
    doc.removeEventListener("dragenter", dragEnterHandler)
    doc.removeEventListener("dragover", dragOverHandler)
    doc.removeEventListener("dragleave", dragLeaveHandler)
    doc.removeEventListener("drop", dropHandler)
  }
}

// Hit-tests the frame document at a client point and resolves it to a
// stamped design element, mirroring editor_controller.js's own
// #_updateHoverFromPoint (elementFromPoint + the nearest
// [data-editor-node-id] ancestor) -- kept as its own small copy here
// rather than shared, since hover and drag resolve independent state
// (hover box vs. drop descriptor) and the two call sites have no reason to
// stay coupled just because the lookup they start from looks the same.
// @return {id, rect} for the stamped element under the point, or null.
export function hitTestStamped(doc, x, y) {
  if (!doc || !doc.elementFromPoint) return null
  const el = doc.elementFromPoint(x, y)
  const target = el && el.closest ? el.closest("[data-editor-node-id]") : null
  if (!target) return null
  return { id: target.getAttribute("data-editor-node-id"), rect: target.getBoundingClientRect() }
}
