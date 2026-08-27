// Makes the design editor's Inspector rail (docs-editor-pane-inspector,
// editor/show.html.erb) user-resizable by dragging the handle that sits
// between it and the centre pane. A purely presentational concern -- this
// controller knows nothing about design-tree nodes or the editor's own
// data model, only a width in px -- which is exactly why it is its own
// small controller instead of more surface on editor_controller.js.
//
// ## How the width actually resizes the pane
//
// docs.css sizes .docs-editor-pane-inspector (lg+ only -- see that rule's
// own comment for what happens below the breakpoint) from a
// --docs-editor-inspector-width custom property, read with a fallback so
// the pane still has a sane width for the instant before this controller's
// connect() runs, and for a host with JS disabled entirely. #_applyWidth
// sets that property inline on the panel target; nothing else touches it.
//
// ## Drag vs. keyboard
//
// Two independent ways to move the handle, both funnelled through
// #_setWidth so they can never disagree about clamping or persistence:
//   - pointerdown (wired declaratively, data-action) starts a drag;
//     pointermove/pointerup/pointercancel are only ever listened for while
//     one is in progress, so they're attached/detached imperatively here
//     rather than sitting on data-action for the whole controller
//     lifetime (same shape as editor_controller.js's own frame-pointer
//     listeners).
//   - keydown (also data-action) moves the handle by one STEP per
//     ArrowLeft/ArrowRight press, or snaps straight to MIN_WIDTH/MAX_WIDTH
//     on Home/End -- the WAI-ARIA "window splitter" pattern the handle's
//     role="separator" + aria-value* attributes below implement.
//
// ## Persistence
//
// Stored under workspace.js's INSPECTOR_WIDTH_KEY (see that module's own
// header, which is the authoritative list of keys this editor owns) --
// imported rather than duplicating the "tabler-ui-docs-editor:" prefix
// here. Read once in connect(), written on pointerup and on every
// keyboard adjustment, never mid-drag (a write per pointermove tick would
// be needless churn for a value nothing but the next page load reads).
import { Controller } from "@hotwired/stimulus"
import { INSPECTOR_WIDTH_KEY } from "controllers/tabler_ui/docs/editor/workspace"

// Narrow enough that the Inspector's own field labels stop reading
// comfortably below this -- no reason to let a drag go further than that.
const MIN_WIDTH = 220
// Wide enough to be a genuinely useful property panel; capped well short
// of "wide enough to swallow the centre pane" -- .docs-editor-pane-centre's
// own min-width (docs.css) is the other half of that guarantee, so a
// viewport this max alone wouldn't fit still leaves the canvas something.
const MAX_WIDTH = 480
const DEFAULT_WIDTH = 320
const STEP = 16

export default class extends Controller {
  static targets = ["handle", "panel"]

  connect() {
    this.width = this._clampWidth(this._loadStoredWidth())
    this._applyWidth()

    // Bound once so add/removeEventListener see the same function
    // reference on the way out (disconnect(), and #_endDrag mid-drag).
    this._onDragMove = this._onDragMove.bind(this)
    this._onDragEnd = this._onDragEnd.bind(this)
  }

  disconnect() {
    // Covers the vanishingly unlikely case of a Turbo swap mid-drag --
    // the drag-only listeners below must never outlive this controller.
    this._endDrag()
  }

  // data-action="pointerdown->tabler-ui--docs-editor-inspector-resize#startDrag"
  startDrag(event) {
    // Only the primary mouse button (or a touch/pen contact, whose
    // `button` reads 0 too) starts a drag -- a right- or middle-click on
    // the handle should do nothing.
    if (event.button !== 0) return

    this._dragStartX = event.clientX
    this._dragStartWidth = this.width
    this._pointerId = event.pointerId

    // Keeps this element receiving pointermove/pointerup even once a fast
    // drag carries the pointer outside the handle's own narrow hit area --
    // without capture, the drag would silently stop tracking the moment
    // the cursor left those few pixels.
    this.handleTarget.setPointerCapture(event.pointerId)
    this.handleTarget.addEventListener("pointermove", this._onDragMove)
    this.handleTarget.addEventListener("pointerup", this._onDragEnd)
    this.handleTarget.addEventListener("pointercancel", this._onDragEnd)

    // Prevents the browser's own touch scroll/zoom gestures from
    // competing with the drag on a touch device.
    event.preventDefault()
  }

  _onDragMove(event) {
    if (event.pointerId !== this._pointerId) return

    // The handle sits to the LEFT of the panel it resizes -- dragging it
    // leftward (pointer clientX decreasing) widens the panel, so the
    // delta is start-minus-current, not the other way round.
    const delta = this._dragStartX - event.clientX
    this._setWidth(this._dragStartWidth + delta)
  }

  _onDragEnd(event) {
    if (event.pointerId !== this._pointerId) return
    this._endDrag()
    this._persistWidth()
  }

  _endDrag() {
    if (this._pointerId !== undefined && this.handleTarget.hasPointerCapture(this._pointerId)) {
      this.handleTarget.releasePointerCapture(this._pointerId)
    }
    this.handleTarget.removeEventListener("pointermove", this._onDragMove)
    this.handleTarget.removeEventListener("pointerup", this._onDragEnd)
    this.handleTarget.removeEventListener("pointercancel", this._onDragEnd)
    this._pointerId = undefined
  }

  // data-action="keydown->tabler-ui--docs-editor-inspector-resize#adjustWithKeyboard"
  // The WAI-ARIA window-splitter pattern this handle's role="separator"
  // implements: ArrowLeft/ArrowRight nudge it by STEP, Home/End jump
  // straight to the clamped extremes. Any other key is left alone (no
  // preventDefault) so Tab, Shift+Tab etc keep working normally.
  adjustWithKeyboard(event) {
    if (event.key === "ArrowLeft") {
      this._setWidth(this.width + STEP)
    } else if (event.key === "ArrowRight") {
      this._setWidth(this.width - STEP)
    } else if (event.key === "Home") {
      this._setWidth(MIN_WIDTH)
    } else if (event.key === "End") {
      this._setWidth(MAX_WIDTH)
    } else {
      return
    }

    event.preventDefault()
    this._persistWidth()
  }

  _setWidth(width) {
    this.width = this._clampWidth(width)
    this._applyWidth()
  }

  _applyWidth() {
    this.panelTarget.style.setProperty("--docs-editor-inspector-width", `${this.width}px`)
    this.handleTarget.setAttribute("aria-valuenow", String(this.width))
    this.handleTarget.setAttribute("aria-valuemin", String(MIN_WIDTH))
    this.handleTarget.setAttribute("aria-valuemax", String(MAX_WIDTH))
  }

  _clampWidth(width) {
    return Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, width))
  }

  _loadStoredWidth() {
    // Never throws -- same discipline as workspace.js's own #loadWorkspace:
    // a missing key, a disabled/sandboxed localStorage, or a stray
    // non-numeric value all fall back to DEFAULT_WIDTH rather than
    // breaking the page.
    try {
      const raw = localStorage.getItem(INSPECTOR_WIDTH_KEY)
      const parsed = Number.parseInt(raw, 10)
      return Number.isFinite(parsed) ? parsed : DEFAULT_WIDTH
    } catch (error) {
      return DEFAULT_WIDTH
    }
  }

  _persistWidth() {
    // Unlike workspace.js's #saveWorkspace, a failure here is allowed to
    // fail silently -- losing the remembered width is a minor annoyance,
    // never data loss, and there is no user-facing error surface this
    // controller could sensibly report it through.
    try {
      localStorage.setItem(INSPECTOR_WIDTH_KEY, String(this.width))
    } catch (error) {
      // See comment above -- deliberately swallowed.
    }
  }
}
