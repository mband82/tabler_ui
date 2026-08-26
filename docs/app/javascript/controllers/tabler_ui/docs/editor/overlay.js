// Draws non-DOM chrome over the design being previewed in the editor's
// sandboxed <iframe> -- a selection box, a hover box, a floating action
// toolbar, and (added for native drag-and-drop) a drag ghost box, an
// insertion line, and a floating "drop into..." chip menu. None of it may
// ever become part of the design's own DOM: Bootstrap leans hard on direct-child selectors
// (.row > *, .btn-group > .btn, .navbar-nav > li), so inserting so much as
// one wrapper or marker element into the design would visibly change what
// renders, and the live preview has to keep matching what the editor
// exports as .html.erb (editor_controller.js's own header, "the one rule
// everything else here is built around" -- this module's rule is the
// DOM-editing sibling of that one).
//
// This is a dumb renderer of rectangles. It knows nothing about the design
// tree, node ids, the component schema, or how a rect was derived --
// editor_controller.js resolves a selected/hovered node (or a
// editor/drop_target.js descriptor, for the ghost/insertion line/chips) to
// a real element or a plain {left, top, width, height}-shaped rect, and
// hands this module that plus a label string (and, for the toolbar, a
// list of {label, title, onClick} descriptors, or for the chip menu a
// list of {label, onDrop} descriptors -- plain functions either way, not
// tree knowledge). That separation is deliberate: setGhost/setInsertionLine/
// setChips below need no more tree/schema knowledge than setSelection/
// setHover always have -- each draws into its own child of the same root,
// shown and hidden the same way, and this file stays exactly as ignorant
// of the tree as it always was.
//
// One root element, created here and appended to the frame document's
// <body> as a sibling of #tabler-ui-editor-canvas -- never a descendant of
// it, so nothing this module does ever touches the canvas's own subtree.
// `position: fixed` + `pointer-events: none` throughout (see
// editor_canvas.css, which owns every visual rule this module's markup
// carries) so this chrome can never intercept a click meant for the design
// underneath it, and so a rect measured with getBoundingClientRect() lines
// up with the box drawn from it with no scroll-position translation --
// both the measurement and the fixed-position box resolve against the same
// frame viewport, in the same document. Confirmed by hand against the
// running editor: scrolling the frame document moves an already-shown
// selection box out of alignment (expected -- see
// editor_controller.js#_repositionOverlay, which re-measures and
// re-applies the rect on frame scroll for exactly this reason) but never
// introduces an outer-page offset.
//
// The toolbar is the one exception to pointer-events: none -- see its own
// comment below for why re-enabling it there is still safe.
const ROOT_ID = "tabler-ui-editor-overlay-root"

// Minimum breathing room, in px, between a box's own rect and a label, the
// toolbar, or the chip menu drawn next to it -- kept as named constants
// rather than magic numbers since #_positionLabel, #_positionToolbar and
// #showChips all apply the same flip-and-clamp logic against them.
const LABEL_GAP = 4
const TOOLBAR_GAP = 6
const CHIPS_GAP = 6

// @param doc the frame document (contentDocument of the Preview iframe) --
//   never the outer editor page's own document; see this file's header.
// @return {
//   setSelection(rect, label), clearSelection(),
//   setHover(rect, label), clearHover(),
//   setToolbar(rect, buttons), clearToolbar(),
//   setGhost(rect, label, valid), clearGhost(),
//   setInsertionLine(rect), clearInsertionLine(),
//   setChips(rect, chips), clearChips(),
//   destroy()
// }
export function createOverlay(doc) {
  const root = doc.createElement("div")
  root.id = ROOT_ID
  root.className = "docs-editor-canvas-overlay-root"
  doc.body.appendChild(root)

  const selection = buildBox(doc, "selection")
  const hover = buildBox(doc, "hover")
  const toolbar = buildToolbar(doc)
  const ghost = buildBox(doc, "ghost")
  const insertionLine = buildLine(doc)
  const chipsMenu = buildChips(doc)
  root.appendChild(selection.box)
  root.appendChild(hover.box)
  root.appendChild(toolbar.box)
  root.appendChild(ghost.box)
  root.appendChild(insertionLine)
  root.appendChild(chipsMenu.box)

  return {
    setSelection(rect, label) {
      showBox(selection, rect, label)
    },

    clearSelection() {
      hideBox(selection)
    },

    setHover(rect, label) {
      showBox(hover, rect, label)
    },

    clearHover() {
      hideBox(hover)
    },

    // `rect` is a plain {left, top, width, height} -- for a real hovered
    // element it comes straight off getBoundingClientRect() the same as
    // every other box here; for a "drop appends to an empty/unhovered
    // root" descriptor (editor/drop_target.js's `position: "append"`)
    // editor_controller.js instead sizes it off the canvas element itself
    // (see drop_target.js's ROOT_GHOST_HEIGHT). `valid` toggles the
    // -invalid modifier class (editor_canvas.css) -- see this file's
    // header on why validity is advisory only: it changes how the ghost
    // LOOKS, never whether the drop is allowed to happen.
    setGhost(rect, label, valid) {
      ghost.box.classList.toggle("docs-editor-canvas-box-ghost-invalid", valid === false)
      showBox(ghost, rect, label)
    },

    clearGhost() {
      hideBox(ghost)
    },

    // `rect` is {left, top, width} -- a thin band, not a full box (see
    // #buildLine below for why this is a separate element shape from
    // every other piece of chrome here, all of which are 4-bordered
    // boxes). `top` is already the exact insertion y-coordinate
    // (drop_target.js's insertionRect: the hovered rect's own top edge for
    // a "before" drop, its bottom edge for "after") -- this function does
    // no further offsetting, it only draws the line where it's told.
    setInsertionLine(rect) {
      if (!rect) {
        insertionLine.hidden = true
        return
      }
      insertionLine.style.left = `${rect.left}px`
      insertionLine.style.top = `${rect.top}px`
      insertionLine.style.width = `${rect.width}px`
      insertionLine.hidden = false
    },

    clearInsertionLine() {
      insertionLine.hidden = true
    },

    // `chips` is [{ label, onDrop }] in display order -- one chip per
    // container editor/drop_target.js's resolver found (a component's
    // empty slots, or -- mid-reorder of an existing builder_item -- an
    // existing left/right-shaped items container; see that file's own
    // header). `rect` is a point, not a real element's box (editor_
    // controller.js passes the drag's current cursor position, zero-sized
    // -- "near the cursor" is the whole reason this is a floating menu
    // rather than chips positioned over each container: an empty slot
    // renders no DOM at all, so there is no rendered position to anchor to
    // for one of those). Rebuilt from scratch on every call, same
    // reasoning as #setToolbar's own comment -- every onDrop closure here
    // closes over whichever chip descriptor THIS call was made with.
    // `dropEffect` ("move" or "copy") is a single string shared by every
    // chip in this menu, not per-chip tree knowledge -- editor_controller.js
    // derives it once per drag from whether `this._dragState.sourceNodeId`
    // is set (a canvas-node move vs. a brand-new palette node), the same
    // fact #_onFrameDragOver already uses to pick the ghost's own
    // dropEffect. Passed through rather than hardcoded here so a chip's
    // hover cursor always matches the drag's real `effectAllowed`
    // (mismatched, the browser silently coerces dropEffect to "none" and
    // shows a permanently "refused" cursor even over a legal chip).
    setChips(rect, chips, dropEffect) {
      showChips(doc, chipsMenu, rect, chips, dropEffect)
    },

    clearChips() {
      chipsMenu.box.hidden = true
    },

    // `buttons` is [{ label, title, onClick }] in display order -- label
    // is set via innerHTML so a caller can pass an HTML entity (an arrow
    // glyph, say) without this module needing to know what any of them
    // mean. Rebuilt from scratch on every call rather than diffed against
    // the previous set: five buttons is nothing to recreate, and it
    // guarantees every onClick closure in the DOM right now closes over
    // whatever node id was current when THIS call was made -- no stale
    // callback left over from a previous selection can ever fire.
    setToolbar(rect, buttons) {
      showToolbar(doc, toolbar, rect, buttons)
    },

    clearToolbar() {
      toolbar.box.hidden = true
    },

    // Removes the root and, with it, every element createOverlay appended
    // to the frame document -- including the toolbar's and chip menu's
    // own button listeners, which go with their (now detached) elements.
    // Kept as an
    // explicit method rather than leaving callers to remove() the root
    // themselves so that a later phase which adds a listener of its own
    // directly on `doc` (dragging a ghost, say) has one obvious place to
    // tear it down, the same way editor_controller.js already pairs every
    // _onFrameLoad listener with a _detachFrameListeners counterpart.
    destroy() {
      root.remove()
    }
  }
}

// One box + label pair, shared shape for both selection and hover -- see
// editor_canvas.css's .docs-editor-canvas-box / -selection / -hover / and
// .docs-editor-canvas-label rules for how `kind` selects their look.
function buildBox(doc, kind) {
  const box = doc.createElement("div")
  box.className = `docs-editor-canvas-box docs-editor-canvas-box-${kind}`
  box.hidden = true

  const label = doc.createElement("div")
  label.className = `docs-editor-canvas-label docs-editor-canvas-label-${kind}`
  box.appendChild(label)

  return { box, label }
}

// The floating action toolbar drawn next to the selected element. A
// sibling of the selection/hover boxes, not a child of the selection box
// the way its label is -- the label's position is defined relative to its
// box (see #_positionLabel), but the toolbar has its own flip/clamp
// geometry (#_positionToolbar) and is shown/hidden independently of
// whether a selection box happens to be visible at that instant.
function buildToolbar(doc) {
  const box = doc.createElement("div")
  box.className = "docs-editor-canvas-toolbar"
  box.hidden = true
  return { box }
}

// The insertion line is a thin horizontal bar, not a bordered box -- it
// has no label and no flip/clamp positioning (setInsertionLine above sets
// its left/top/width directly from an already-resolved rect), so it gets
// its own single-element shape rather than reusing #buildBox, whose label
// child and box-shadow-free border styling don't apply here.
function buildLine(doc) {
  const line = doc.createElement("div")
  line.className = "docs-editor-canvas-insertion-line"
  line.hidden = true
  return line
}

// The floating "drop into..." chip menu -- a sibling of the toolbar with
// the same shape (a box holding a row of buttons, rebuilt from scratch on
// every #showChips call), but anchored to the drag's cursor position
// rather than to a selected/hovered element's own rect (see #setChips's
// own comment for why: an empty slot renders no DOM at all to anchor a
// per-container chip to).
function buildChips(doc) {
  const box = doc.createElement("div")
  box.className = "docs-editor-canvas-chips"
  box.hidden = true
  return { box }
}

// `rect` is a DOMRect (or any {left, top, width, height}-shaped object) in
// the frame document's own viewport coordinates -- exactly what
// getBoundingClientRect() returns when called inside that document, which
// is the only place editor_controller.js is expected to call it from. A
// falsy rect (the node's element isn't in the DOM right now -- see that
// controller's own reasoning at the call site) hides the box instead of
// drawing a stale one at its last position.
function showBox({ box, label }, rect, text) {
  if (!rect) {
    box.hidden = true
    return
  }
  box.style.left = `${rect.left}px`
  box.style.top = `${rect.top}px`
  box.style.width = `${rect.width}px`
  box.style.height = `${rect.height}px`
  label.textContent = text || ""
  // The label has to be un-hidden (and therefore laid out) BEFORE
  // #_positionLabel measures it below -- offsetWidth/offsetHeight on a
  // display: none element both read 0, which would collapse every label
  // into the top-left corner instead of flipping/clamping against its
  // real size.
  box.hidden = false
  positionLabel(box.ownerDocument.defaultView, label, rect)
}

function hideBox({ box }) {
  box.hidden = true
}

// The label used to be positioned with a fixed CSS offset relative to its
// box (`top: -1.6em`, `left: -1px`) -- simple, but wrong the moment the
// selected element's own top edge sits within 1.6em of the frame
// viewport's top: the label was drawn 1.6em above THAT, i.e. partly or
// wholly above y=0 and clipped out of the visible frame entirely (measured
// live against the running editor: -17px). This function replaces that
// fixed offset with the same flip-and-clamp rule #_positionToolbar uses:
// prefer sitting just above the target rect, flip to just below it if
// "above" would clip, and as a last resort (the rect's own top is already
// off-screen, or the viewport is shorter than the label is tall) anchor
// inside the rect's own top edge rather than drawing nothing. Horizontal
// position is clamped the same way. If the target rect itself has
// scrolled entirely out of the frame viewport, the label is hidden outright
// -- there is no sane position for "attached to an element you can't see"
// -- while the box it's attached to is left alone (it clips naturally at
// the viewport edge, which reads correctly with no help from JS).
//
// Positioned with `position: fixed` (see editor_canvas.css) rather than
// relative to its box like the old offset was, because the flip/clamp math
// below already resolves against the frame viewport -- recomputing it a
// second time into box-local coordinates would just be the same
// arithmetic done twice for no benefit.
function positionLabel(view, label, rect) {
  const pos = flipAndClamp(view, rect, label.offsetWidth, label.offsetHeight, LABEL_GAP)
  if (!pos) {
    label.hidden = true
    return
  }
  label.hidden = false
  label.style.left = `${pos.left}px`
  label.style.top = `${pos.top}px`
}

// Rebuilds the toolbar's buttons from `buttons` and positions the whole
// bar with the same flip-and-clamp rule as the label (see
// #_positionLabel's header for the reasoning -- this is its sibling for a
// wider, taller piece of chrome rather than a one-line pill). A falsy rect
// or an empty button list hides the toolbar outright.
function showToolbar(doc, toolbar, rect, buttons) {
  if (!rect || !buttons || buttons.length === 0) {
    toolbar.box.hidden = true
    return
  }

  toolbar.box.innerHTML = ""
  buttons.forEach(({ label, title, onClick }) => {
    const btn = doc.createElement("button")
    btn.type = "button"
    btn.className = "docs-editor-canvas-toolbar-btn"
    btn.innerHTML = label
    if (title) btn.title = title
    // stopPropagation so a click here never also reaches the frame's own
    // capture-phase click listener as a "click on the design" -- that
    // listener (editor_controller.js#_onFrameClick) walks up from
    // event.target looking for [data-editor-node-id], which a toolbar
    // button never carries, so in practice it would just no-op, but
    // stopping it here is the difference between "happens to be harmless
    // today" and "guaranteed never to matter what that handler does next".
    btn.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      onClick(event)
    })
    toolbar.box.appendChild(btn)
  })

  // Same measure-before-position requirement #_positionLabel documents:
  // un-hide first so offsetWidth/offsetHeight reflect the buttons just
  // built, not a stale (or zero, if this is the toolbar's first paint)
  // size from before.
  toolbar.box.hidden = false
  const pos = flipAndClamp(doc.defaultView, rect, toolbar.box.offsetWidth, toolbar.box.offsetHeight, TOOLBAR_GAP)
  if (!pos) {
    toolbar.box.hidden = true
    return
  }
  toolbar.box.style.left = `${pos.left}px`
  toolbar.box.style.top = `${pos.top}px`
}

// Rebuilds the chip menu's buttons from `chips` and positions the whole
// menu with the same flip-and-clamp rule #showToolbar uses (see
// #_positionLabel's header for the reasoning) -- CHIPS_GAP rather than
// TOOLBAR_GAP so the menu doesn't visually collide with whatever ghost/
// insertion-line chrome editor_controller.js is also drawing at the same
// cursor position. A falsy rect or an empty chip list hides the menu
// outright, the same contract #showToolbar has for an empty button list.
//
// Each chip responds to dragover/drop, not click -- "dropping on a chip"
// is the whole interaction (this is still one continuous native drag,
// never released and restarted), so the listeners have to be the same
// pair dnd.js's own frame-level ones are (preventDefault on dragover so
// the browser will fire drop at all; see that module's header). Both also
// stopPropagation so the frame-level doc listeners (DnD.attachFrameDropTarget,
// wired in editor_controller.js#_onFrameLoad) never also see the same
// dragover/drop as a second, competing resolution once the pointer is
// sitting directly over a chip -- there is no [data-editor-node-id]
// ancestor for elementFromPoint to find here anyway (the chip menu is a
// sibling of the canvas, not inside it), but stopping propagation is what
// keeps the LAST resolved chip target from being clobbered by a stray
// "pointer is over nothing stamped" tick while it sits still over a chip.
function showChips(doc, chipsMenu, rect, chips, dropEffect) {
  if (!rect || !chips || chips.length === 0) {
    chipsMenu.box.hidden = true
    return
  }

  chipsMenu.box.innerHTML = ""
  chips.forEach(({ label, onDrop }) => {
    const chip = doc.createElement("button")
    chip.type = "button"
    chip.className = "docs-editor-canvas-chip"
    chip.textContent = label
    chip.addEventListener("dragenter", (event) => {
      event.preventDefault()
      event.stopPropagation()
    })
    chip.addEventListener("dragover", (event) => {
      event.preventDefault()
      event.stopPropagation()
      if (event.dataTransfer) event.dataTransfer.dropEffect = dropEffect || "move"
    })
    chip.addEventListener("drop", (event) => {
      event.preventDefault()
      event.stopPropagation()
      onDrop(event)
    })
    chipsMenu.box.appendChild(chip)
  })

  // Same measure-before-position requirement #_positionLabel documents.
  chipsMenu.box.hidden = false
  const pos = flipAndClamp(doc.defaultView, rect, chipsMenu.box.offsetWidth, chipsMenu.box.offsetHeight, CHIPS_GAP)
  if (!pos) {
    chipsMenu.box.hidden = true
    return
  }
  chipsMenu.box.style.left = `${pos.left}px`
  chipsMenu.box.style.top = `${pos.top}px`
}

// Shared geometry for the label, the toolbar, and the chip menu: given a `width` x
// `height` piece of chrome that wants to sit just above `rect`'s top edge,
// return the {left, top} (frame-viewport px, i.e. what `position: fixed`
// or a rect-relative `position: absolute` under the full-viewport root
// both resolve the same way) that keeps it fully on screen --
//
//   1. default: `gap` px above the rect's own top edge.
//   2. if that clips off the top of the viewport, flip to `gap` px below
//      the rect's bottom edge instead.
//   3. if NEITHER fits (the rect is taller than the viewport, so both
//      "above" and "below" are themselves off-screen), give up trying to
//      sit outside the rect at all and anchor flush with its own top edge
//      -- still visible, just overlapping the element instead of framing
//      it, which is the best any placement can do at that point.
//
// Horizontal position is independently clamped so the chrome's left/right
// edge never renders past the viewport's own left/right edge, regardless
// of which of the three vertical cases applied.
//
// @return null if `rect` itself has no on-screen extent left at all (fully
//   scrolled out of the frame viewport on any side) -- there is no
//   position that would make sense for chrome attached to something you
//   cannot see, so the caller hides it rather than clamping it to a
//   meaningless edge.
function flipAndClamp(view, rect, width, height, gap) {
  const viewportWidth = view.innerWidth
  const viewportHeight = view.innerHeight

  if (rect.right <= 0 || rect.left >= viewportWidth || rect.bottom <= 0 || rect.top >= viewportHeight) {
    return null
  }

  let top
  if (rect.top - height - gap >= 0) {
    top = rect.top - height - gap // default: just above the element
  } else if (rect.top + rect.height + height + gap <= viewportHeight) {
    top = rect.top + rect.height + gap // flip: just below the element
  } else {
    top = rect.top // neither fits -- anchor inside the element's own top edge
  }

  let left = rect.left
  if (left < 0) left = 0
  if (left + width > viewportWidth) left = Math.max(0, viewportWidth - width)

  return { left, top }
}
