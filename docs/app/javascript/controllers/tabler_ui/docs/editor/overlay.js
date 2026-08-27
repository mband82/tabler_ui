// Draws non-DOM chrome over the design being previewed in the editor's
// sandboxed <iframe> -- a selection box, a hover box, a floating action
// toolbar, (added for native drag-and-drop) a drag ghost box, an
// insertion line, and a floating "drop into..." chip menu, and (added for
// design-editor layout guides) an unbounded, id-keyed set of labelled
// container outlines. None of it may
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
// of the tree as it always was. setGuides is the same contract stretched
// to an unbounded N: editor_controller.js resolves every server slot
// marker and every row/column tree node to a {id, left, top, width,
// height, label} rect itself -- this module still never learns what a
// "slot" or a "row" is, only that it was handed a rect with that id and
// that string to draw this time.
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

// How close (px, both axes) two guides' own top-left corners have to be
// for #setGuides to treat them as landing "in the same spot" and hide the
// second label rather than let it overlap the first -- see that method's
// own comment for the two ways this happens (a row whose lone column
// fills it exactly -- an EXACT match -- and a column's own child starting
// a few px further in for its own border -- a NEAR match) and why a small
// tolerance, not exact equality, is what this actually needs. Close to,
// but not measured from, the guide label's own rendered height (~15.6px
// at this file's 0.65rem/1.4 line-height, confirmed by hand against the
// running editor) -- rounded up on the theory that two corners closer
// together than one label's own height are certain to have overlapping
// labels, not read off the DOM every call to confirm it precisely.
const GUIDE_LABEL_COLLISION_TOLERANCE = 16

// @param doc the frame document (contentDocument of the Preview iframe) --
//   never the outer editor page's own document; see this file's header.
// @return {
//   setSelection(rect, label), clearSelection(),
//   setHover(rect, label), clearHover(),
//   setToolbar(rect, buttons), clearToolbar(),
//   setGhost(rect, label, valid, wrap), clearGhost(),
//   setInsertionLine(rect, orientation), clearInsertionLine(),
//   setWrapOutline(rect, label), clearWrapOutline(),
//   setChips(rect, chips), clearChips(),
//   setGuides(rects), clearGuides(), setGuidesMuted(muted),
//   destroy()
// }
export function createOverlay(doc) {
  const root = doc.createElement("div")
  root.id = ROOT_ID
  root.className = "docs-editor-canvas-overlay-root"
  doc.body.appendChild(root)

  // Guides are appended first so every other piece of chrome below (which
  // all share this same root) paints on top of them -- a selection or
  // hover box landing on the same element a guide also outlines must never
  // read as ambiguous about which one is "in front".
  const guidesRoot = doc.createElement("div")
  guidesRoot.className = "docs-editor-canvas-guides"
  root.appendChild(guidesRoot)
  // id => {box, label} -- see #setGuides below for why this is a
  // long-lived Map diffed in place rather than rebuilt from scratch like
  // #showChips/#showToolbar's much smaller (five-ish items) button lists.
  const guideBoxes = new Map()

  const selection = buildBox(doc, "selection")
  const hover = buildBox(doc, "hover")
  const toolbar = buildToolbar(doc)
  const ghost = buildBox(doc, "ghost")
  const insertionLine = buildLine(doc)
  // The wrap outline (see #setWrapOutline below) shares .buildBox's shape
  // with selection/hover/ghost -- a box + its own label -- but is
  // APPENDED BEFORE the ghost, not after: a wrap outline covers the whole
  // hovered element while the ghost drawn for that same drag tick sits
  // INSIDE half of it (editor_controller.js#_paintDragGhost's "wrap"
  // case), and the ghost has to paint on top of the outline it's nested
  // inside of for that to read correctly, not the other way around.
  const wrapOutline = buildBox(doc, "wrap")
  const chipsMenu = buildChips(doc)
  root.appendChild(selection.box)
  root.appendChild(hover.box)
  root.appendChild(toolbar.box)
  root.appendChild(wrapOutline.box)
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
    // LOOKS, never whether the drop is allowed to happen. `wrap` (new,
    // optional -- every existing caller before the wrap feature omits it,
    // which is falsy the same as explicit `false`) toggles the distinct
    // -wrap modifier class editor_controller.js#_paintDragGhost's "wrap"
    // case sets, so a compound "build a new row" drop reads as visibly
    // different chrome from an ordinary insert rather than the same dashed
    // primary-hue box in a different position.
    setGhost(rect, label, valid, wrap) {
      ghost.box.classList.toggle("docs-editor-canvas-box-ghost-invalid", valid === false)
      ghost.box.classList.toggle("docs-editor-canvas-box-ghost-wrap", !!wrap)
      showBox(ghost, rect, label)
    },

    clearGhost() {
      hideBox(ghost)
    },

    // `rect` is {left, top, width} for a HORIZONTAL line (the original
    // top/bottom-edge case) or {left, top, height} for a VERTICAL one (the
    // new left/right-edge case, drop_target.js's horizontal bands) -- a
    // thin band, not a full box (see #buildLine below for why this is a
    // separate element shape from every other piece of chrome here, all of
    // which are 4-bordered boxes). `top`/`left` are already the exact
    // insertion coordinate (drop_target.js's insertionRect) -- this
    // function does no further offsetting, it only draws the line where
    // it's told, in the axis `orientation` says. `orientation` defaults to
    // "horizontal" -- every caller from before the wrap feature passes no
    // third argument at all, and must keep drawing exactly the bar it
    // always has.
    setInsertionLine(rect, orientation = "horizontal") {
      if (!rect) {
        insertionLine.hidden = true
        return
      }
      const vertical = orientation === "vertical"
      insertionLine.classList.toggle("docs-editor-canvas-insertion-line-vertical", vertical)
      insertionLine.style.left = `${rect.left}px`
      insertionLine.style.top = `${rect.top}px`
      // Only the dimension THIS orientation actually uses is set -- the
      // other is left as whatever it was (editor_canvas.css's own
      // vertical-modifier rule overrides the fixed one CSS alone would
      // otherwise apply), so a horizontal line never carries a stale
      // inline height from a previous vertical tick or vice versa.
      if (vertical) {
        insertionLine.style.height = `${rect.height}px`
      } else {
        insertionLine.style.width = `${rect.width}px`
      }
      insertionLine.hidden = false
    },

    clearInsertionLine() {
      insertionLine.hidden = true
    },

    // The "this whole element is about to become one half of a new row"
    // outline drawn for a `position: "wrap"` descriptor -- see editor_
    // controller.js#_paintDragGhost's own comment for why this needs to be
    // visually distinct from the ordinary ghost box it's drawn alongside
    // (a wrap is a bigger structural change than a plain insert). `rect`
    // is the hovered element's own full rect, unlike the ghost drawn at
    // the same tick (that one is sized to half of it) -- see #buildBox's
    // shared shape for why this reuses the same box+label construction
    // selection/hover/ghost already use rather than inventing a new one.
    setWrapOutline(rect, label) {
      showBox(wrapOutline, rect, label)
    },

    clearWrapOutline() {
      hideBox(wrapOutline)
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

    // `rects` is [{id, left, top, width, height, label}] -- one entry per
    // container editor_controller.js#_collectGuideRects found this tick
    // (every server-decorated slot marker, plus every row/column node in
    // the current tree), in no particular order. Diffed against the guide
    // boxes already on screen BY ID, reusing a box/label pair across calls
    // for any id that survives from one recompute to the next -- this is
    // the one place in this file that deliberately does NOT follow
    // #setChips/#setToolbar's "rebuild from scratch" pattern: that pattern
    // is fine for five buttons rebuilt on a user action, but guides can
    // number in the dozens and recompute on every scroll/resize tick (see
    // editor_controller.js#_repositionGuides), so tearing down and
    // rebuilding every box every time would be real, avoidable DOM churn
    // on the hot path this feature is most likely to make slow.
    //
    // No flip-and-clamp here (contrast #_positionLabel/#showToolbar/
    // #showChips, all of which call #flipAndClamp) -- a guide's label is
    // pinned to its own box's top-left corner by CSS alone
    // (.docs-editor-canvas-guide-label, editor_canvas.css), so nothing
    // here ever reads label.offsetWidth/offsetHeight. That is a
    // deliberate trade, not an oversight: flipAndClamp's synchronous
    // layout read is affordable once per selection/hover/toolbar change,
    // but not fifty times on every animation frame a scroll produces.
    //
    // Two nested containers routinely resolve to top-left corners that are
    // the same or close enough to read as the same -- a row whose one,
    // full-span column fills it precisely (Bootstrap's row/column
    // negative-margin-vs-padding cancelling out to a BYTE-for-byte
    // identical rect) is one case, but confirmed live against a real
    // nested design, a column's own child (a card, its own slot markers
    // starting a few px further in for the card's own border) lands only a
    // few px off the column's corner, not exactly on it -- and every guide
    // label pinned to "its own box's top-left corner" still overlaps
    // there, because two ~16px-tall labels a few px apart overlap just as
    // unreadably as two pinned to the identical pixel. `claimedCorners`
    // below finds every guide whose corner lands within
    // GUIDE_LABEL_COLLISION_TOLERANCE of one already claimed this call and
    // hides ONLY that guide's LABEL, never its box -- the box stays drawn
    // (so the container is still outlined and still a visible drop
    // target), only the caption that would have overlapped disappears.
    // This was tried first the other way, offsetting every colliding label
    // downward by a fixed step instead of hiding it, and that approach has
    // a real correctness hole a suppress-only fix does not: nudging a
    // label down by a fixed distance from ITS OWN box's top ignores
    // whatever ELSE already sits just below that box, so clearing one
    // collision can silently create a new one against an unrelated
    // neighbour (confirmed live: pushing "column"'s label clear of "row"
    // landed it on top of the next slot guide's own "body" label two rows
    // away). Suppression cannot do that -- a hidden label renders nowhere,
    // so fixing one collision can never create another. The trade this
    // accepts is real (a corner with three coinciding guides shows only
    // one caption, not three), but guides are chrome, not data -- the tree
    // itself, the Structure tab, and the Inspector are all still there for
    // "what nested inside what" -- and every guide's own BOX is still
    // drawn and still distinguishable by size even when its label is not,
    // so nothing about the design's actual structure becomes unreadable,
    // only one redundant caption at a shared corner does. Which guide
    // keeps its label is simply whichever reaches this loop first --
    // #_collectGuideRects' own fixed collection order (slot markers, then
    // shared-slot markers, then a tree walk), not a deliberately ranked
    // "more specific wins" rule -- because ranking arbitrary guide kinds
    // by specificity is exactly the kind of tree/schema knowledge this
    // file's header says it deliberately never has. Still no text
    // measurement: every compare is arithmetic against `rect.left`/
    // `rect.top`, numbers this function already has. Worst case this is
    // one pass over the corners claimed so far per guide (O(n) guides x
    // O(n) corners), not the single Map lookup exact-match would have
    // been, but guides top out in the dozens for any design this editor
    // can build (see guideBoxes' own doc above), so even the worst case
    // here is a few hundred cheap number comparisons, not a cost this hot
    // path needs to fear. Recomputed from scratch on every call (never
    // carried over from the previous one) so a collision that stops
    // applying -- a sibling gains real content, the tree changes shape --
    // un-hides itself the very next tick rather than leaving a label
    // hidden for no reason still in effect.
    setGuides(rects) {
      const seen = new Set()
      const claimedCorners = [] // [{left, top}], this call only
      rects.forEach((rect) => {
        seen.add(rect.id)
        let entry = guideBoxes.get(rect.id)
        if (!entry) {
          entry = buildGuideBox(doc)
          guideBoxes.set(rect.id, entry)
          guidesRoot.appendChild(entry.box)
        }
        entry.box.style.left = `${rect.left}px`
        entry.box.style.top = `${rect.top}px`
        entry.box.style.width = `${rect.width}px`
        entry.box.style.height = `${rect.height}px`
        entry.label.textContent = rect.label || ""

        const collides = claimedCorners.some((c) => (
          Math.abs(c.left - rect.left) < GUIDE_LABEL_COLLISION_TOLERANCE && Math.abs(c.top - rect.top) < GUIDE_LABEL_COLLISION_TOLERANCE
        ))
        if (!collides) claimedCorners.push({ left: rect.left, top: rect.top })
        entry.label.hidden = collides
      })

      // Anything left over from a previous call that isn't in THIS set no
      // longer has a container to outline (its node was deleted, its slot
      // just gained real content that supplied its own wrapper elsewhere,
      // or guides were toggled off entirely) -- remove it rather than
      // leave a stale box drawn over whatever now occupies that position.
      guideBoxes.forEach((entry, id) => {
        if (seen.has(id)) return
        entry.box.remove()
        guideBoxes.delete(id)
      })
    },

    // Removes every guide box currently on screen. Called when guides are
    // toggled off (editor_controller.js#toggleGuides/#_repositionGuides) --
    // NOT for the duration of a native drag any more. A drag used to clear
    // guides outright on the theory that they'd visually compete with the
    // drag's own dashed ghost box, insertion line and chip menu; that made
    // guides vanish exactly when they earn their keep most, since an empty
    // container being dragged into is invisible without one. #setGuidesMuted
    // below is what a drag reaches for instead -- it recedes the same boxes
    // this method would have torn down, rather than tearing them down.
    clearGuides() {
      guideBoxes.forEach(({ box }) => box.remove())
      guideBoxes.clear()
    },

    // Toggled at drag start/end (editor_controller.js#paletteDragStart,
    // #_onFrameDragStart, #_endDrag) -- a single class on the shared
    // guides layer rather than a per-box change, so every box AND its
    // label recede together with one rule (editor_canvas.css's
    // .docs-editor-canvas-guides-muted) and can never drift out of sync
    // with each other the way toggling something on each box individually
    // could. Purely a look: it draws nothing and measures nothing, so
    // calling it does not count as a guide recompute -- #_repositionGuides'
    // own doc in editor_controller.js is the place that claim is load-
    // bearing, since a per-dragover-tick recompute is exactly what this
    // feature avoids. Safe to call with no guides on screen at all (the
    // toggle switched off, so guidesRoot has no children right now) -- it
    // still only sets a class, so there is nothing for it to make appear.
    setGuidesMuted(muted) {
      guidesRoot.classList.toggle("docs-editor-canvas-guides-muted", muted)
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

// One guide box + corner-label pair. Deliberately NOT built on #buildBox
// above despite the superficial similarity (a bordered box with a label
// child) -- a guide's label is positioned by plain CSS (top: 0; left: 0
// inside its own box, editor_canvas.css) rather than through
// #positionLabel/#flipAndClamp, so giving it #buildBox's shared shape
// would invite a future edit to wire it through that path by reflex and
// reintroduce the exact synchronous-layout-read cost #setGuides' own
// comment explains this box was built to avoid.
function buildGuideBox(doc) {
  const box = doc.createElement("div")
  box.className = "docs-editor-canvas-guide"

  const label = doc.createElement("div")
  label.className = "docs-editor-canvas-guide-label"
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
