// Pure geometry + placement math for "drag something onto the canvas" --
// both a palette item (a brand-new node) and an existing canvas node being
// reordered (editor_controller.js's #_onFrameDragStart / editor/dnd.js).
// Given the current tree, the schema payload, which stamped element the
// pointer is over (if any), where inside it, and (for a canvas-originated
// drag) which node is being moved, this resolves WHERE a drop would land
// if it happened right now -- nothing here writes to the DOM, touches
// dataTransfer, or holds state across calls. Every call is independent:
// the same inputs always produce the same descriptor.
//
// ## Three bands, not two
//
// A hovered element's own height is split into three vertical bands: the
// top band resolves to "insert before me", the bottom band resolves to
// "insert after me", and the middle band resolves to "into" -- landing
// INSIDE the element, when that means anything for its kind (see
// #resolveInto). Each edge band is BEFORE_FRACTION (equivalently, 1 -
// AFTER_FRACTION) of the element's own height, CAPPED at EDGE_CAP_PX --
// see that constant's own comment for why an uncapped fraction is a bug on
// a wide/tall element, not a feature. When "into" doesn't mean anything (no
// container to land in, or a slot-style/builder-style component with no
// legal container available right now), the middle band falls back to
// whichever edge the pointer is closer to -- see #nearestEdge -- rather
// than resolving to nothing.
//
// ## Four edges, one rule
//
// The pointer's HORIZONTAL position matters too, near a hovered element's
// left/right edges -- #edgeBandFor computes the pointer's distance to each
// of the four edges (top/bottom against the element's own height, left/
// right against its own width) as a FRACTION of the relevant dimension,
// and the smallest of the four wins that "which edge is nearest,
// proportionally" contest, exactly as before this file learned about
// EDGE_CAP_PX. What changed is the second question, "is the nearest edge
// actually close enough to count as an edge band at all": that check now
// compares against whichever is smaller, EDGE_FRACTION or EDGE_CAP_PX
// re-expressed as a fraction of THAT edge's own dimension -- so the band
// itself is still capped in absolute pixels, exactly like the vertical
// three-band rule above, while the "which of the four is nearest"
// determination stays a pure proportional comparison (see EDGE_CAP_PX's
// own comment for why the two questions have to stay separate). This is
// deliberately not "check top, then check left, ..." in sequence: a
// pointer near a corner can satisfy two naive band tests at once, and
// checking in a fixed order would prefer whichever happens to be tested
// first rather than whichever the pointer is actually closer to,
// proportionally. A genuine tie (mathematically possible right on a
// diagonal) breaks in a fixed top/bottom/left/right order, so the result
// is fully deterministic even there.
//
// What a LEFT/RIGHT band resolves to depends on the hovered element's own
// position in the tree (#resolveHorizontalEdge):
//
//   0. the hovered element's own IMMEDIATE parent is one of the schema's
//      `kinds.directChildContainers` (published from Schema::
//      DIRECT_CHILD_CONTAINERS -- card_group, badge_list today): a
//      component whose CSS depends on its slot's own content staying
//      DIRECT children of its root element (card_group's tabler.css rule
//      is a literal `.card-group > .card` combinator; badge_list's
//      `.badges-list` is a `display: flex; gap: ...` row that a nested
//      `row` -- itself flex/wrap with its own negative margins -- would
//      hard-break onto its own line). Wrapping OR joining a column here
//      would nest a row/column between the container and its child,
//      breaking that contract exactly the way this feature exists to
//      avoid -- see Schema::DIRECT_CHILD_CONTAINERS' own doc comment for
//      the full per-component reasoning, including which ROOT_SHARED
//      components were checked and deliberately left out (alert, ribbon,
//      avatar). Resolves to a PLAIN sibling insert in the exact same slot
//      the hovered element already lives in -- no row, no column, just
//      `container.index`/`container.index + 1` -- which is not a
//      consolation prize: a card_group already lays its cards out side by
//      side, so a plain sibling IS the side-by-side result a wrap would
//      otherwise have tried to build differently. Checked before case 1
//      below, and unconditionally (it never falls through to the vertical
//      band on failure, because it never fails once the parent check
//      matches): whether some distant ancestor also happens to be a
//      column-in-row is irrelevant here -- the hovered element sits
//      DIRECTLY inside a direct-child container right now, full stop.
//   1. the hovered element lives INSIDE a column that is itself a direct
//      child of a row -- found by walking UP from the hovered element
//      (#findNearestColumnInRow), not just checking its own immediate
//      container, because a column is normally filled by its own child (a
//      card, say) and that child's edge is the only part of it big enough
//      to actually aim a drag at (see this file's own DRAG_GROW_MIN_SIZE
//      note) -- the hovered element itself sitting directly in the row's
//      `children` (i.e. being that column) is just the nearest-ancestor
//      search terminating immediately, the same case as before this
//      feature existed. Either way, this resolves to a new sibling
//      COLUMN joining that SAME, already-existing row (tree.js#
//      insertColumnBeside) -- never a bare node spliced directly into
//      row.children (row.children only ever holds columns --
//      Tree::ROW_CONTAINER_KINDS) and never a brand-new row nested one
//      level deeper inside the hovered column (case 2 below would do
//      that, which is why this is checked FIRST: a column-in-row already
//      has a grid to join, and joining it beats starting a nested one).
//   2. no such ancestor exists, but `row` is legal directly in the
//      hovered element's own container (root, a slot, a column's own
//      children) -- WRAP the hovered element and the dragged one together
//      into a brand-new row of two columns (tree.js#wrapInRow), ordered
//      by which side the pointer was on, replacing the hovered element
//      where it stood. This is the right call here specifically because
//      case 1 already ruled out "there's an existing row right there to
//      join instead".
//   3. neither applies (no column-in-row ancestor, and `row` isn't legal
//      in the hovered element's own container either) -- there is no
//      legal horizontal drop here, so fall back to the ordinary vertical
//      three-band rule above exactly as if the pointer's horizontal
//      proximity had never been considered, rather than offering an
//      illegal drop.
//
// ## Validity is advisory, never enforcement
//
// #resolveDropTarget's `valid`/`reason` (and, on a "chips" descriptor,
// each chip's own `valid`) exist to drive the drop cursor and how
// editor_controller.js paints the ghost/chips -- nothing else. The server
// (Editor::Tree) is the one real validator, and a tree this module calls
// "invalid" is still handed to the preview endpoint exactly like any other
// edit, coming back as a reported error the same way a bad manual property
// edit already does (see tree.js's own header, "the server ... is the only
// real validator"). Do not start enforcing these rules by refusing to
// perform a drop -- that would make this module a second, drifting copy of
// Editor::Tree's real placement logic. The one exception is dropping a
// node into its own descendant: `valid: false` there is still advisory
// (editor_controller.js still calls Tree.moveNodeTo unconditionally), but
// moveNodeTo's own contract already no-ops that case at the data layer
// (tree.js's own header on #moveNodeTo) -- this module's job is only to
// tell the ghost/chips to *look* refused, not to newly enforce anything.
//
// The placement vocabularies themselves (which kind is legal directly
// under which container) come from the schema payload's `kinds.placement`
// -- published by GET /ui/editor/schema specifically so this file never
// hardcodes its own copy of Tree::ROOT_KINDS / NON_ROW_CONTAINER_KINDS /
// ROW_CONTAINER_KINDS and can't drift from the server's real rules. The
// one deliberate exception is an `items` container: Editor::Tree's own
// normalize_items (docs/lib/tabler_ui/docs/editor/tree.rb) allows
// `builder_item` there and nothing else, a rule the published `placement`
// payload has no list for at all (it only publishes root/non-row/row
// container vocabularies). #resolveContainerChips never needs to consult
// one, though: it only ever proposes an `items`-container chip when
// `draggedKind === "builder_item"` in the first place (see that
// function), so the one kind it could ever offer is already the one kind
// that container accepts -- nothing here re-derives or duplicates Tree's
// rule, it just never has occasion to contradict it.
import { findNode, findContainer, findParent } from "controllers/tabler_ui/docs/editor/tree"

// The fraction of a hovered element's own height, measured from its own
// top edge, that the "insert before" band occupies; symmetrically, the
// "insert after" band starts at (1 - AFTER_FRACTION) and runs to the
// bottom. Everything between the two is the "into" band. Kept as named
// constants (rather than bare numbers) so editor_canvas.css or a future
// tuning pass has one place to read the same split this module enforces.
//
// These are FRACTIONS, not the actual band size -- #bandFor never applies
// either one directly, it applies min(height * BEFORE_FRACTION, EDGE_CAP_PX)
// instead. See EDGE_CAP_PX's own comment (below DRAG_GROW_MIN_SIZE) for why
// the raw fraction alone is the wrong answer on anything but a small
// element.
export const BEFORE_FRACTION = 0.25
export const AFTER_FRACTION = 0.75

// Same idea as BEFORE_FRACTION/AFTER_FRACTION above, but feeding
// #edgeBandFor's four-edge test (this file's header, "Four edges, one
// rule") rather than the vertical-only three-band test those two feed.
// Kept as its own constant, even though it shares BEFORE_FRACTION's value
// today, because the two mean different things geometrically: BEFORE_
// FRACTION is "a fraction of an element's own height, measured from its
// top edge specifically"; EDGE_FRACTION is "how close, as a fraction of
// the relevant dimension, the pointer has to be to whichever edge turned
// out nearest, for ANY of the four". A future tuning pass touching one
// should not accidentally retune the other just because they started
// equal.
//
// Same caveat as BEFORE_FRACTION above: this is a fraction, and #edgeBandFor
// never treats it as the actual band width -- it's capped by EDGE_CAP_PX
// exactly the way the vertical three-band rule is. See EDGE_CAP_PX's own
// comment.
export const EDGE_FRACTION = 0.25

// A dashed placeholder box's nominal height in the "append to an empty (or
// unhovered) root" case, where there is no sibling rect to size the ghost
// against -- editor_controller.js reads this rather than inventing its own
// number, so the two stay in sync without a second constant somewhere else.
export const ROOT_GHOST_HEIGHT = 28

// Drag-only minimum size (px) editor_controller.js#_growSmallDropTargets
// grows an undersized stamped element to, so its own edge bands (BEFORE_
// FRACTION/AFTER_FRACTION/EDGE_FRACTION above) are wide enough to actually
// aim a pointer at. 32px makes an EDGE_FRACTION (0.25) band on an element
// at exactly this size 8px deep -- about as small as a band can get and
// still be reliably hittable with a mouse. Not invented fresh: it's the
// same 2rem editor_canvas.css's own .docs-editor-canvas-empty-container
// rule already uses to solve the identical problem for an empty row/column
// (assuming the frame's default 16px root font size, the same assumption
// that rule already makes) -- reusing it here keeps "how big is big enough
// to aim at" answered by one number in spirit, even though a JS constant
// and a CSS rule can't literally share a value across that boundary.
export const DRAG_GROW_MIN_SIZE = 32

// The hard ceiling, in pixels, on how deep an edge band (BEFORE_FRACTION/
// AFTER_FRACTION's vertical bands, EDGE_FRACTION's four-edge bands) is ever
// allowed to get, regardless of how large the hovered element is. Reusing
// DRAG_GROW_MIN_SIZE's own value rather than a second, independently-tuned
// number: DRAG_GROW_MIN_SIZE already answers "how big does an element need
// to be for a quarter of it to be reliably hittable" for the SMALL end
// (growing an undersized element up to this size during a drag -- this
// file's own header, "Drag-only minimum size"); this constant answers the
// same "comfortably clickable" question from the LARGE end, and there's no
// reason the two should disagree about what a comfortably-sized band looks
// like just because one is a floor and the other a ceiling.
//
// The bug this exists to fix: #bandFor and #edgeBandFor originally applied
// BEFORE_FRACTION/EDGE_FRACTION (0.25) as a bare fraction of the hovered
// element's own dimension, with nothing capping the result. That's fine on
// a small element -- 0.25 of a 32px-tall card is a razor-thin but workable
// 8px -- but on anything larger it stops meaning "the edge" at all: a
// card_group rendering at 694px wide has 174px LEFT and RIGHT bands under
// the bare fraction, well over a third of its total width each, so a
// user aiming for the middle "drop the card inside" region routinely lands
// in "wrap" or "column" instead and gets a spurious row/column nest -- the
// exact defect this constant exists to close. Capping each band at
// min(dimension * fraction, EDGE_CAP_PX) keeps the two régimes:
//
//   * dimension <= EDGE_CAP_PX / fraction (128px, at today's 0.25/32):
//     the fraction is still the smaller number, so nothing changes here --
//     a small element's bands stay PROPORTIONAL to its own size (the
//     "keep small elements usable" requirement), same as before this fix.
//   * dimension > 128px: EDGE_CAP_PX is the smaller number and wins --
//     the band is a fixed EDGE_CAP_PX regardless of how much bigger the
//     element gets, so the "into" middle keeps growing to fill essentially
//     the whole element on anything large, rather than the two edge bands
//     eating an ever-larger, unbounded share of it.
//
// Applied per axis, independently, from that axis's OWN dimension --
// #bandFor caps against `height` alone (it only ever produces top/bottom
// bands), #edgeBandFor computes one capped fraction from `height` for its
// top/bottom candidates and a SEPARATE one from `width` for its left/right
// candidates, so a wide-but-short element (this file's own card_group
// measurement: 694 x 32) gets a tight horizontal cap and a
// fraction-dominated (uncapped) vertical one in the very same call, each
// answering only for its own dimension.
export const EDGE_CAP_PX = DRAG_GROW_MIN_SIZE

// The five components whose slot content renders straight into the
// component's own root element, no dedicated wrapper of its own -- the
// exact set this file's header already names under `hoveredSlotName`
// (docs/lib/tabler_ui/docs/editor/slot_parts.rb's ROOT_SHARED registry).
// Hand-kept here too: docs/lib is not bundled into this JS build, and
// nothing schema.js publishes carries this distinction (Schema#kinds_payload
// only ever lists a component's slot NAMES, never how each one is wired to
// the DOM) -- five names is small enough that a second, by-hand copy is the
// pragmatic answer, the same trade this file already made for
// `hoveredSlotName` itself.
export const ROOT_SHARED_COMPONENTS = ["alert", "avatar", "badge_list", "card_group", "ribbon"]

// The subset of ROOT_SHARED_COMPONENTS above whose SLOT is the only thing
// that can ever put visible content on screen -- used by
// editor_controller.js#_stampEmptyContainers to decide which empty
// root-shared components need the same at-rest minimum-height treatment an
// empty row/column already gets (that method's own doc). Deliberately NOT
// all five:
//
//   * alert/badge_list/card_group/ribbon: badge_list and card_group's own
//     templates (app/components/tabler_ui/{badge_list,card_group}/
//     _component.html.erb) render literally nothing besides
//     `if slots.present?(:body)` -- an empty slot IS an empty element, no
//     other option can ever produce a competing answer. alert and ribbon
//     both have OTHER content paths too (alert's title/text/icon options,
//     ribbon's text/icon) that can render something even with this slot
//     empty, but each already has its own CSS floor for that case
//     (ribbon's own `min-height: 2rem` in tabler.css; alert's 0.75rem
//     top+bottom padding alone) that makes stamping this class here at
//     worst a harmless no-op, at best the same usability floor row/column
//     already get. Grouped with the two purely-slot-driven components
//     rather than split out because the risk of stamping them is nil.
//   * avatar: excluded outright. Its root-shared slot (`overlay`) is
//     supplementary -- a status dot layered onto an avatar that ALWAYS
//     renders an image, initials, or a generated identicon on its own
//     (Avatar::Component's template is an unconditional if/elsif/else,
//     one branch always runs) -- so an empty `overlay` slot never means an
//     empty avatar the way an empty `body` slot means an empty card_group.
//     Worse, avatar has real, intentionally-small size variants below this
//     file's own DRAG_GROW_MIN_SIZE floor (avatar-xs is 1.25rem/20px,
//     avatar-xxs 1rem/16px, tabler.css) -- forcing a 2rem minimum height
//     onto one just because its unrelated overlay slot is empty would
//     visibly inflate it past its own deliberately chosen size, exactly
//     the "disturb a component that already has content" failure this
//     feature has to avoid.
export const ROOT_SHARED_EMPTY_COMPONENTS = ["alert", "badge_list", "card_group", "ribbon"]

// The tree-only half of "does this node need the empty-root-shared
// min-height stamp" -- mirrors how editor_controller.js#_stampEmptyContainers
// already answers the equivalent question for a row/column from
// `node.children` alone, no DOM involved: this reads only `node.kind`,
// `node.name`, and `node.slots`, never anything measured. A node with no
// `slots` object at all (a freshly-added component, never given any block)
// counts as empty, same as one whose every slot array is present but
// zero-length.
//
// @param node a tree node (editor/tree.js shape), or null/undefined
// @return {Boolean}
export function isEmptyRootSharedComponent(node) {
  if (!node || node.kind !== "component" || !ROOT_SHARED_EMPTY_COMPONENTS.includes(node.name)) return false
  if (!node.slots || typeof node.slots !== "object") return true
  return Object.values(node.slots).every((arr) => !Array.isArray(arr) || arr.length === 0)
}

// @param tree the current file's design tree (editor_controller.js
//   #_currentTree()), or null/undefined if no file is open.
// @param schema the /ui/editor/schema payload (editor_controller.js
//   #_schema), or null before it has loaded -- placement/limit checks are
//   skipped (permissive) rather than guessed at until it's available.
// @param hoveredNodeId the id of the stamped element under the pointer, or
//   null if the pointer is over no stamped element at all (empty canvas,
//   or dead space around the design).
// @param hoveredRect the hovered element's getBoundingClientRect(), or
//   null when hoveredNodeId is null.
// @param hoveredSlotName the `data-editor-slot` value carried by the
//   EXACT matched element (editor_controller.js#_hitTestDragTarget), or
//   null. Only ever set under decoration (Renderer's `decorate:` flag --
//   `data-editor-slot` doesn't exist in the DOM otherwise) and only for a
//   PRECISE slot's own dedicated wrapper -- never for a ROOT_SHARED slot,
//   which stamps the different `data-editor-slot-shared` attribute on the
//   component's root instead (Renderer#stamp_shared_slot) and is
//   deliberately not read into this field, so a root-shared component
//   (alert, avatar, badge_list, card_group, ribbon) keeps resolving
//   through the chip path below exactly as it always has. When set, the
//   middle band resolves straight into that named slot instead of
//   offering a chip for it -- see #resolveDirectSlot.
// @param pointerX the drag's current clientX, in the same (frame-viewport)
//   coordinate space as hoveredRect -- feeds #edgeBandFor's left/right
//   edge test alongside pointerY's top/bottom one (this file's header,
//   "Four edges, one rule").
// @param pointerY the drag's current clientY, in the same (frame-viewport)
//   coordinate space as hoveredRect.
// @param draggedKind the kind of the thing being dragged -- a palette
//   item's node kind ("row", "column", "heading", "text", "partial",
//   "component"), or, for a canvas-originated drag, the actual kind of the
//   node under the pointer at dragstart (which can also be "builder_item").
// @param draggedNodeId null for a palette drag (there is no existing node
//   yet); for a canvas-originated drag, the id of the node being moved --
//   used only to refuse landing inside that node's own subtree (see the
//   header above).
// @return {
//   parentId, container, index,     -- where Tree.insertAt/moveNodeTo would
//                                       place the node (container is
//                                       "children", "items", or
//                                       "slot__<name>"), or all null when
//                                       position is "chips" (there is no
//                                       single target -- see `chips` below)
//   position,                       -- "before" | "after" | "into" |
//                                       "append" | "chips" | "wrap" |
//                                       "column"
//   edge,                           -- "top" | "bottom" | "left" | "right",
//                                       set only for "before"/"after"/
//                                       "column", null otherwise -- which
//                                       physical edge the band came from,
//                                       driving the ghost/insertion-line
//                                       orientation (see `lineOrientation`)
//   lineOrientation,                 -- "horizontal" | "vertical", set for
//                                       "before"/"after"/"wrap"/"column",
//                                       null otherwise -- which way
//                                       editor_controller.js should draw
//                                       the insertion line: horizontal for
//                                       a top/bottom edge, vertical for a
//                                       left/right one, a wrap, or a
//                                       column.
//   anchorRect,                     -- the hoveredRect this was resolved
//                                       against, or null for "append"
//   insertionRect,                  -- {left, top, width} for a horizontal
//                                       line, {left, top, height} for a
//                                       vertical one -- set only for
//                                       "before"/"after"/"wrap"/"column",
//                                       null otherwise
//   wrapTargetId,                   -- set only for "wrap": the id of the
//                                       node being wrapped (tree.js#
//                                       wrapInRow's own `targetId`), null
//                                       otherwise
//   wrapSide,                       -- set only for "wrap": "before" | "after"
//                                       -- which column the DRAGGED node
//                                       lands in, relative to wrapTargetId's
//                                       own (see tree.js#wrapInRow), null
//                                       otherwise
//   columnTargetId,                 -- set only for "column": the id of the
//                                       EXISTING column the new one joins as
//                                       a sibling (tree.js#
//                                       insertColumnBeside's own
//                                       `columnId`), null otherwise
//   columnSide,                     -- set only for "column": "before" |
//                                       "after" -- which side of
//                                       columnTargetId the new column lands
//                                       on (see tree.js#insertColumnBeside),
//                                       null otherwise
//   columnSpan,                     -- set for "wrap" and "column": the
//                                       {breakpoint: value} span object to
//                                       give the new column(s)
//                                       (#defaultColumnSpan), null
//                                       otherwise
//   chips,                          -- [{label, parentId, container,
//                                       index, valid, reason}], set only
//                                       for position "chips", null
//                                       otherwise
//   valid, reason                   -- advisory only, see header. For
//                                       "chips", true iff at least one
//                                       chip is valid.
// }
export function resolveDropTarget({ tree, schema, hoveredNodeId, hoveredRect, hoveredSlotName = null, pointerX, pointerY, draggedKind, draggedNodeId = null }) {
  if (!tree) {
    return {
      parentId: null, container: null, index: 0, position: "append",
      edge: null, lineOrientation: null, anchorRect: null, insertionRect: null,
      wrapTargetId: null, wrapSide: null, columnTargetId: null, columnSide: null, columnSpan: null,
      chips: null, valid: false, reason: "no file is open"
    }
  }

  let target = null
  // hoveredNodeId === tree.id can't actually happen -- the root fragment
  // is never stamped with data-editor-node-id (editor_controller.js's own
  // task brief notes this) -- but guarding it costs nothing and keeps
  // #resolveAgainstElement from ever being asked to find "the root's own
  // container", which doesn't mean anything.
  if (hoveredNodeId && hoveredRect && hoveredNodeId !== tree.id) {
    target = resolveAgainstElement(tree, schema, hoveredNodeId, hoveredRect, hoveredSlotName, pointerX, pointerY, draggedKind, draggedNodeId)
  }
  if (!target) target = resolveAgainstRoot(tree)

  return { ...target, ...validateTarget(tree, schema, target, draggedKind, draggedNodeId) }
}

// --- geometry --------------------------------------------------------------

function bandFor(rect, pointerY) {
  // Capped at EDGE_CAP_PX -- see that constant's own comment. Both edges
  // share one band size (BEFORE_FRACTION and AFTER_FRACTION are symmetric,
  // 0.25 and 1 - 0.25) so a single min() covers both; a zero-height rect
  // (should not happen -- see #edgeBandFor's own zero-dimension note) just
  // collapses both edges onto `rect.top`, which is no worse than the
  // element itself having no usable middle to begin with.
  const bandHeight = rect.height > 0 ? Math.min(rect.height * BEFORE_FRACTION, EDGE_CAP_PX) : 0
  const beforeEdge = rect.top + bandHeight
  const afterEdge = rect.bottom - bandHeight
  if (pointerY < beforeEdge) return "before"
  if (pointerY > afterEdge) return "after"
  return "into"
}

// Used when the pointer is in the middle band but there's no "into" target
// to land in (see #resolveInto) -- falls back to whichever edge the
// pointer is nearer, so the middle band never resolves to nothing.
function nearestEdge(rect, pointerY) {
  const midpoint = rect.top + rect.height / 2
  return pointerY < midpoint ? "before" : "after"
}

// Which of an element's four edges (if any) the pointer is close enough to
// for an edge band to apply -- see this file's header, "Four edges, one
// rule", for the corner-determinism reasoning this implements: each edge's
// distance from the pointer as a FRACTION of the relevant dimension
// (top/bottom against height, left/right against width), the smallest of
// the four wins -- that part answers only "which edge is the pointer
// proportionally nearest to", and is unaffected by EDGE_CAP_PX. Whether
// that nearest edge is actually CLOSE ENOUGH to count as an edge band at
// all (rather than "into") is a second, separate question: `bandFraction`
// re-expresses EDGE_CAP_PX as a fraction of that same candidate's own
// dimension and takes whichever of it and EDGE_FRACTION is smaller --
// exactly the min(dimension * fraction, EDGE_CAP_PX) rule EDGE_CAP_PX's own
// comment describes, just phrased in fraction-space so it can be compared
// directly against `candidate.fraction` -- and the nearest edge's band
// applies only if its own fraction is within ITS OWN bandFraction.
// Computed once per axis (`verticalBandFraction`/`horizontalBandFraction`)
// rather than per candidate: top and bottom always share height, left and
// right always share width. A zero-sized dimension (should not happen --
// #_growSmallDropTargets exists specifically so a hovered element always
// has real size during a drag -- but division by zero would otherwise
// produce NaN/Infinity comparisons that could resolve unpredictably)
// forces that axis's two candidates to Infinity, so they can never win the
// "smallest of four" comparison below; forcing that axis's bandFraction to
// 0 is belt-and-suspenders for the same case, since a fraction of Infinity
// already fails any `<= bandFraction` test regardless of what bandFraction
// is.
//
// @return "top" | "bottom" | "left" | "right" | "into"
function edgeBandFor(rect, pointerX, pointerY) {
  const verticalBandFraction = rect.height > 0 ? Math.min(EDGE_FRACTION, EDGE_CAP_PX / rect.height) : 0
  const horizontalBandFraction = rect.width > 0 ? Math.min(EDGE_FRACTION, EDGE_CAP_PX / rect.width) : 0
  const candidates = [
    { edge: "top", fraction: rect.height > 0 ? (pointerY - rect.top) / rect.height : Infinity, bandFraction: verticalBandFraction },
    { edge: "bottom", fraction: rect.height > 0 ? (rect.bottom - pointerY) / rect.height : Infinity, bandFraction: verticalBandFraction },
    { edge: "left", fraction: rect.width > 0 ? (pointerX - rect.left) / rect.width : Infinity, bandFraction: horizontalBandFraction },
    { edge: "right", fraction: rect.width > 0 ? (rect.right - pointerX) / rect.width : Infinity, bandFraction: horizontalBandFraction }
  ]
  // Strict `<` keeps the FIRST candidate on an exact tie (mathematically
  // possible right on a diagonal from the element's center) -- top, then
  // bottom, then left, then right, in the fixed order `candidates` is
  // built in above -- so a tie is still fully deterministic, never a
  // coin flip.
  const nearest = candidates.reduce((closest, candidate) => (candidate.fraction < closest.fraction ? candidate : closest))
  return nearest.fraction <= nearest.bandFraction ? nearest.edge : "into"
}

function resolveAgainstElement(tree, schema, hoveredNodeId, hoveredRect, hoveredSlotName, pointerX, pointerY, draggedKind, draggedNodeId) {
  const container = findContainer(tree, hoveredNodeId)
  const parent = findParent(tree, hoveredNodeId)
  if (!container || !parent) return null

  const key = containerKeyFor(parent, container.array)
  if (!key) return null

  const nearEdge = edgeBandFor(hoveredRect, pointerX, pointerY)
  if (nearEdge === "left" || nearEdge === "right") {
    const horizontal = resolveHorizontalEdge(tree, schema, hoveredNodeId, hoveredRect, parent, key, container, nearEdge, draggedKind)
    if (horizontal) return horizontal
    // Neither horizontal case applies (this file's header, "Four edges,
    // one rule", case 3) -- fall through to the vertical-only three-band
    // rule below exactly as if the pointer's horizontal proximity had
    // never been considered.
  }

  // #edgeBandFor speaks a four-edge vocabulary ("top"/"bottom"/"left"/
  // "right"/"into"); everything below this point (and the descriptor's own
  // `position` field) speaks the two-sided "before"/"after"/"into" one
  // #bandFor already used before this feature existed. left/right was
  // either fully handled by #resolveHorizontalEdge above (an early return)
  // or explicitly falls back to re-resolving with #bandFor alone -- the
  // ORIGINAL vertical-only rule, deliberately ignoring the horizontal
  // proximity that "won" above (this file's header, case 3). A top/bottom/
  // into result, by contrast, is #edgeBandFor's own authoritative answer
  // already (it already weighed all four edges to get there) and just
  // needs translating into the same vocabulary, not a second, independent
  // vertical-only computation that could disagree with it.
  let band
  if (nearEdge === "left" || nearEdge === "right") {
    band = bandFor(hoveredRect, pointerY)
  } else if (nearEdge === "top") {
    band = "before"
  } else if (nearEdge === "bottom") {
    band = "after"
  } else {
    band = "into"
  }

  if (band === "into") {
    const hoveredNode = findNode(tree, hoveredNodeId)
    // The matched element itself names a slot (see #resolveDirectSlot and
    // this file's header on `hoveredSlotName`) -- that's a stronger, more
    // specific answer than "offer a chip for every empty slot", so it
    // takes priority over #resolveInto's chip-menu path below and, unlike
    // that path, deliberately does NOT fall back to chips when the named
    // slot itself can't take this drop (occupied): the element under the
    // pointer already committed to one specific slot, so if that slot is
    // out, the only thing left to offer is a sibling via the edge bands,
    // not a menu of the component's OTHER slots the pointer isn't even
    // over.
    const into = hoveredSlotName
      ? resolveDirectSlot(hoveredNode, hoveredSlotName, hoveredRect)
      : resolveInto(tree, schema, hoveredNode, hoveredRect, draggedKind, draggedNodeId)
    if (into) return into
    band = nearestEdge(hoveredRect, pointerY) // no container to land in -- fall back to the nearer edge
  }

  const index = band === "before" ? container.index : container.index + 1

  return {
    parentId: parent.id,
    container: key,
    index,
    position: band,
    edge: band === "before" ? "top" : "bottom",
    lineOrientation: "horizontal",
    anchorRect: hoveredRect,
    insertionRect: {
      left: hoveredRect.left,
      top: band === "before" ? hoveredRect.top : hoveredRect.bottom,
      width: hoveredRect.width
    },
    wrapTargetId: null,
    wrapSide: null,
    columnTargetId: null,
    columnSide: null,
    columnSpan: null,
    chips: null
  }
}

// The pointer is within the (capped, see EDGE_CAP_PX) left/right band of
// the hovered element's own edge (#edgeBandFor already decided that) --
// resolves what THAT means for the container the hovered element actually
// sits in, per this file's header ("Four edges, one rule") and the two
// cases it describes.
//
// @return a complete descriptor for either case, or null if neither
//   applies -- the caller (#resolveAgainstElement) falls back to the
//   ordinary vertical bands for that case.
function resolveHorizontalEdge(tree, schema, hoveredNodeId, hoveredRect, parent, key, container, edge, draggedKind) {
  // Case 0: the hovered element's own immediate parent is a direct-child
  // container (this file's header, case 0, has the full reasoning) -- a
  // plain sibling insert in the container it already sits in, never a
  // wrap or a joined column. `directChildContainers` degrades to an empty
  // list with no schema loaded yet, same "no safe answer without the
  // published vocabulary" stance case 2's own `placement` lookup takes
  // below -- this case just no-ops instead of matching anything, falling
  // through to case 1/2/3 exactly as if this case didn't exist yet, rather
  // than guessing.
  const directChildContainers = (schema && schema.kinds && schema.kinds.directChildContainers) || []
  if (parent.kind === "component" && directChildContainers.includes(parent.name)) {
    const side = edge === "left" ? "before" : "after"
    return {
      parentId: parent.id,
      container: key,
      index: side === "before" ? container.index : container.index + 1,
      position: side,
      edge,
      lineOrientation: "vertical",
      anchorRect: hoveredRect,
      insertionRect: {
        left: edge === "left" ? hoveredRect.left : hoveredRect.right,
        top: hoveredRect.top,
        height: hoveredRect.height
      },
      wrapTargetId: null,
      wrapSide: null,
      columnTargetId: null,
      columnSide: null,
      columnSpan: null,
      chips: null
    }
  }

  // Case 1: the hovered element lives inside a column that is itself a
  // direct child of a row -- possibly several levels down (a card filling
  // its column, say), possibly the column itself (the nearest-ancestor
  // walk starting AT the hovered element and finding a match on its very
  // first step) -- see #findNearestColumnInRow and this file's header. A
  // new sibling COLUMN joins that SAME row, before or after the ancestor
  // column found, rather than wrapping anything: row.children only ever
  // holds columns (Tree::ROW_CONTAINER_KINDS), so a bare node spliced in
  // there directly would silently break the grid, and this row already
  // exists, so there's no reason to nest a second one one level deeper the
  // way case 2's wrap would. `hoveredRect` (the innermost hovered
  // element's own rect, e.g. the card's, not the ancestor column's -- this
  // function is never handed the column's own measured rect) still anchors
  // the insertion line/ghost: the pointer had to be near enough to the
  // hovered element's own edge to get here at all, and that edge sits hard
  // up against its column's edge in practice (a column is normally filled
  // by its child), so the small offset from any grid gutter/padding is not
  // worth plumbing a second getBoundingClientRect() through the caller for.
  const nearestColumn = findNearestColumnInRow(tree, hoveredNodeId)
  if (nearestColumn) {
    const side = edge === "left" ? "before" : "after"
    return {
      parentId: nearestColumn.rowId,
      container: "children",
      index: side === "before" ? nearestColumn.index : nearestColumn.index + 1,
      position: "column",
      edge,
      lineOrientation: "vertical",
      anchorRect: hoveredRect,
      insertionRect: {
        left: edge === "left" ? hoveredRect.left : hoveredRect.right,
        top: hoveredRect.top,
        height: hoveredRect.height
      },
      wrapTargetId: null,
      wrapSide: null,
      columnTargetId: nearestColumn.columnId,
      columnSide: side,
      columnSpan: defaultColumnSpan(schema),
      chips: null
    }
  }

  // Case 2: WRAP -- reached only when case 1 above found no existing
  // row to join. Legal only when `row` is itself legal directly in the
  // hovered element's own container (root, a slot, a column's own
  // children; never a row's, already ruled out by case 1 having failed to
  // find a column-in-row ancestor -- if the hovered element WERE a row's
  // own child, case 1 would have matched on it directly). Needs the schema
  // both for the placement vocabulary (to check legality at all) and the
  // column span vocabulary (#defaultColumnSpan) -- with no schema loaded
  // yet, there is no safe way to do either, so this reports "nothing
  // horizontal here" rather than guessing (permissive-by-omission, not
  // permissive-by-guess -- contrast #validateSingleTarget's "no schema,
  // allow everything" stance, which is about ADVISORY validity, not about
  // whether enough information exists to build the descriptor's own
  // required fields).
  const placement = schema && schema.kinds && schema.kinds.placement
  if (!placement) return null

  const allowedKinds = allowedKindsFor(tree, parent.id, key, placement)
  if (!allowedKinds.includes("row")) return null // row isn't legal here either -- nothing horizontal to offer (case 3)

  return {
    parentId: parent.id,
    container: key,
    index: container.index,
    position: "wrap",
    edge,
    lineOrientation: "vertical",
    anchorRect: hoveredRect,
    insertionRect: {
      left: edge === "left" ? hoveredRect.left : hoveredRect.right,
      top: hoveredRect.top,
      height: hoveredRect.height
    },
    wrapTargetId: hoveredNodeId,
    wrapSide: edge === "left" ? "before" : "after",
    columnTargetId: null,
    columnSide: null,
    columnSpan: defaultColumnSpan(schema),
    chips: null
  }
}

// Walks UP from `hoveredNodeId` (starting with the hovered node itself,
// then each successive owner via tree.js#findParent) looking for the
// NEAREST ancestor that is both a `column` and has a `row` as its own
// parent -- i.e. a column sitting exactly where Tree::ROW_CONTAINER_KINDS
// says a column always must (columns are never legal anywhere else), which
// in practice means the first `column`-kind node found IS that node,
// checked defensively rather than assumed. "Nearest" matters (this file's
// header, case 1): a card several levels deep inside a NESTED row/column
// structure must join the nested row it actually sits in, not some
// outer/distant one further up the tree, so this stops at the first match
// rather than continuing to walk past it.
//
// @return {columnId, rowId, index} -- `index` is the matched column's own
//   position in its row's `children` (tree.js#findContainer's `.index`),
//   already available here so the caller never has to re-look it up --
//   or null if the walk reaches the tree's root without finding one (the
//   hovered element isn't inside any row at all, or only inside a
//   row/column nested inside something else entirely, e.g. a slot with no
//   row in it).
function findNearestColumnInRow(tree, hoveredNodeId) {
  let currentId = hoveredNodeId
  while (currentId) {
    const node = findNode(tree, currentId)
    if (!node) return null

    if (node.kind === "column") {
      const parent = findParent(tree, currentId)
      if (!parent || parent.kind !== "row") return null // shouldn't happen (see this function's own header) -- treat defensively as "no row to join"
      const container = findContainer(tree, currentId)
      if (!container) return null
      return { columnId: currentId, rowId: parent.id, index: container.index }
    }

    const parent = findParent(tree, currentId)
    if (!parent) return null // reached the root with no column-in-row ancestor found
    currentId = parent.id
  }
  return null
}

// A "sensible default" span for the two columns tree.js#wrapInRow's caller
// (editor_controller.js#_applyWrapDrop) creates -- read from the SAME
// published vocabulary the property panel's own span control already uses
// (schema.kinds.column -- Schema#kinds_payload, Contract::SPAN_KEYS/
// SPAN_VALUES on the server) rather than inventing a key/value pair this
// file has no way to know is still legal. "base" -- always the first key,
// Contract::SPAN_KEYS is ["base", *Breakpoint::ALL] -- applies at every
// breakpoint with no media query at all, which is what makes the two
// columns sit side by side unconditionally rather than only past some
// screen width; 6, half of Bootstrap's 12-column grid, is picked out of
// spanValues (falling back sensibly if a future value set ever omitted it)
// rather than hardcoded, so two of these fill exactly one row.
function defaultColumnSpan(schema) {
  const columnMeta = schema && schema.kinds && schema.kinds.column
  const keys = (columnMeta && columnMeta.spanKeys) || ["base"]
  const values = (columnMeta && columnMeta.spanValues) || [12]
  const numericValues = values.filter((value) => typeof value === "number")
  const half = numericValues.includes(6) ? 6 : numericValues[Math.floor(numericValues.length / 2)] || 12
  return { [keys[0]]: half }
}

// The pointer is over a slot's own dedicated wrapper element (a real,
// stamped, measurable node -- Renderer's decoration mode gives even an
// EMPTY precise slot one, so #resolveAgainstElement's caller always has
// real geometry to check the band against here) -- land directly inside
// THAT slot, no chip menu involved. This only exists because decoration
// changed the premise #resolveContainerChips below was built on: chips
// were designed for a slot that renders zero DOM at all (nothing to
// anchor a drop target to, so a cursor-anchored menu was the only
// option), which is still true with guides off, still true for a
// ROOT_SHARED slot (no wrapper of its own to hand this function in the
// first place -- see this file's header on `hoveredSlotName`), and still
// true for a builder-style `items` container (chips' OTHER case, entirely
// unrelated to slots -- see #resolveContainerChips). None of those apply
// once the pointer is over a real, on-screen, labelled slot element.
//
// @return the same {parentId, container, index, position: "into", ...}
//   shape #resolveInto's row/column/fragment branch returns, or null if
//   `slotName` is already occupied -- a slot holds at most one node
//   (editor_controller.js#_handleStructureMove's own comment), checked
//   here against the TREE's own `slots` data, never the DOM (the DOM
//   placeholder only ever exists for an EMPTY slot in the first place --
//   Renderer#emit_decorated_slots -- so there is nothing in the DOM an
//   occupied slot's real content could be confused with anyway). null
//   sends the caller to the edge-band fallback, not to the chip menu --
//   see the caller's own comment for why.
function resolveDirectSlot(hoveredNode, slotName, hoveredRect) {
  if (!hoveredNode || hoveredNode.kind !== "component") return null

  const occupant = (hoveredNode.slots && hoveredNode.slots[slotName]) || []
  if (occupant.length > 0) return null

  return {
    parentId: hoveredNode.id,
    container: `slot__${slotName}`,
    index: 0,
    position: "into",
    anchorRect: hoveredRect,
    insertionRect: null,
    chips: null
  }
}

// The middle band's "land inside the hovered element" case. Three kinds of
// hovered element, in the order this checks them:
//
//   1. row/column/fragment -- a plain container that takes children
//      directly, no chip menu needed: land at the end of its own
//      `children` array. (These three don't have their own schema entry
//      at all -- "component" is the only kind #resolveContainerChips ever
//      looks components up for -- so there's nothing to offer chips FOR
//      here even if we wanted to.)
//   2. a component with EXACTLY ONE legal chip target right now -- resolve
//      straight into it, the same way #resolveDirectSlot just above
//      already resolves a precise slot's own visible wrapper with no menu
//      at all. Popping a one-item chip menu is pure friction when there is
//      only ever one thing the menu could offer: the user would have to
//      spot and hit a small floating button to do the only thing on offer,
//      instead of the drop just working. See #validateSingleTarget's own
//      `container !== "items"` guard for the one place this branch and
//      case 3 below have to agree on purpose: an `items` container is
//      legal here for the identical reason #legalChips already decided it
//      was before this ever got called with exactly one candidate.
//   3. a component with SEVERAL legal chip targets (a card with more than
//      one empty slot, say) -- genuinely ambiguous, so this returns a
//      "chips" descriptor instead of a parentId/container/index triple;
//      the user has to pick one.
//   4. anything else (a component with nothing to offer, or a leaf kind
//      like heading/text/partial/builder_item that never accepts
//      children at all) -- no "into" landing exists; return null so the
//      caller falls back to the nearer edge.
function resolveInto(tree, schema, hoveredNode, hoveredRect, draggedKind, draggedNodeId) {
  if (!hoveredNode) return null

  if (["row", "column", "fragment"].includes(hoveredNode.kind)) {
    const children = Array.isArray(hoveredNode.children) ? hoveredNode.children : []
    return {
      parentId: hoveredNode.id,
      container: "children",
      index: children.length,
      position: "into",
      anchorRect: hoveredRect,
      insertionRect: null,
      chips: null
    }
  }

  const chips = legalChips(tree, schema, hoveredNode, draggedKind, draggedNodeId)
  if (chips.length === 0) return null

  if (chips.length === 1) {
    const [chip] = chips
    return {
      parentId: chip.parentId,
      container: chip.container,
      index: chip.index,
      position: "into",
      anchorRect: hoveredRect,
      insertionRect: null,
      chips: null
    }
  }

  return {
    parentId: null,
    container: null,
    index: null,
    position: "chips",
    anchorRect: hoveredRect,
    insertionRect: null,
    chips
  }
}

// The pointer is over no stamped element at all -- append to the file's
// root children. There is no sibling to draw an insertion line against
// (editor_controller.js falls back to sizing the ghost off the canvas
// element itself; see ROOT_GHOST_HEIGHT above).
function resolveAgainstRoot(tree) {
  const children = Array.isArray(tree.children) ? tree.children : []
  return {
    parentId: tree.id,
    container: "children",
    index: children.length,
    position: "append",
    anchorRect: null,
    insertionRect: null,
    chips: null
  }
}

// `arrayRef` is the exact array reference findContainer returned (a
// reference INTO the tree, per tree.js's own contract) -- so identity
// comparison against `parent`'s own children/items/each slot array
// unambiguously names which one it is, the same "slot__<name>" / "children"
// / "items" encoding tree.js's insertAt/moveNodeTo already use for
// `container`.
function containerKeyFor(parent, arrayRef) {
  if (parent.children === arrayRef) return "children"
  if (parent.items === arrayRef) return "items"
  if (parent.slots) {
    const slotName = Object.keys(parent.slots).find((key) => parent.slots[key] === arrayRef)
    if (slotName) return `slot__${slotName}`
  }
  return null
}

// --- chips (drop-into-container menu) --------------------------------

// One chip per container a "land inside" drop could legally use right
// now, for a hovered `component`-kind node. Two shapes (see this file's
// task-brief header, "Which containers to offer"):
//
//   * slot-style (schema `components[name].slots` is non-empty): one chip
//     per EMPTY slot -- a slot holds at most one node
//     (editor_controller.js#_handleStructureMove already enforces this),
//     so an occupied one isn't offered. A component with every slot
//     filled returns [] here, which #resolveInto above treats as "no
//     into target" and falls back to the edge bands.
//   * builder-style (schema `components[name].builder` present) AND the
//     thing being dragged is itself an existing `builder_item`
//     (`draggedKind === "builder_item"`): this is the one builder case
//     that's a genuine MOVE rather than a brand-new insert -- reordering
//     an existing builder_item among the `:root`-level methods that take
//     `block: "items"` (today, only navbar's `left`/`right`). One chip
//     per such method that already has a matching builder_item present
//     in the hovered component's own `items` array (there's no sensible
//     "create a left/right container from nothing" chip -- only an
//     EXISTING one is a move target). A palette drag (draggedKind is
//     never "builder_item" for one -- see palette.js, which only ever
//     drags row/column/heading/text/partial/component) or a foreign node
//     always gets [] here: only a builder_item is ever legal inside an
//     `items` array at all (this file's header), so nothing else could
//     ever land there.
//
// Plain row/column/fragment containers never reach this function --
// #resolveInto handles them directly, with no chip menu at all (see that
// function's own comment).
function resolveContainerChips(hoveredNode, schema, draggedKind) {
  if (!hoveredNode || hoveredNode.kind !== "component") return []
  const meta = schema && schema.components && schema.components[hoveredNode.name]
  if (!meta) return []

  const slots = Array.isArray(meta.slots) ? meta.slots : []
  if (slots.length > 0) {
    return slots
      .filter((slotName) => {
        const occupant = (hoveredNode.slots && hoveredNode.slots[slotName]) || []
        return occupant.length === 0
      })
      .map((slotName) => ({
        label: titleCase(slotName),
        parentId: hoveredNode.id,
        container: `slot__${slotName}`,
        index: 0
      }))
  }

  if (meta.builder && draggedKind === "builder_item") {
    const rootMethods = (meta.builder.root) || {}
    const itemsMethodNames = Object.keys(rootMethods).filter((name) => rootMethods[name].block === "items")
    if (itemsMethodNames.length === 0) return []

    const items = Array.isArray(hoveredNode.items) ? hoveredNode.items : []
    return itemsMethodNames
      .map((methodName) => {
        const child = items.find((n) => n.kind === "builder_item" && n.method === methodName)
        if (!child) return null // no existing left/right container to move into -- nothing to offer
        const childItems = Array.isArray(child.items) ? child.items : []
        return {
          label: titleCase(methodName),
          parentId: child.id,
          container: "items",
          index: childItems.length
        }
      })
      .filter((chip) => chip != null)
  }

  return []
}

function titleCase(name) {
  return name.charAt(0).toUpperCase() + name.slice(1)
}

// #resolveContainerChips's raw candidates, filtered down to the ones this
// drag could actually legally use right now: not inside the dragged
// node's own subtree (see this file's header on why that's advisory-only
// here), and -- for a slot chip -- kind-legal per the published
// `placement.nonRowContainerKinds` (an `items` chip skips this check
// entirely; see this file's header for why it doesn't need it). A chip
// that fails either check is dropped from the list outright rather than
// kept-but-disabled: the same "falls back to edge bands when there's
// nothing offerable" rule #resolveInto already applies to an empty chip
// list applies here too, not a new "disabled chip" UI concept.
function legalChips(tree, schema, hoveredNode, draggedKind, draggedNodeId) {
  const candidates = resolveContainerChips(hoveredNode, schema, draggedKind)
  const placement = schema && schema.kinds && schema.kinds.placement

  return candidates.filter((chip) => {
    if (draggedNodeId && isWithinSubtree(tree, draggedNodeId, chip.parentId)) return false
    if (chip.container === "items") return true // see resolveContainerChips's header
    if (!placement) return true
    return allowedKindsFor(tree, chip.parentId, chip.container, placement).includes(draggedKind)
  })
}

// @return true if `candidateId` is `ancestorId` itself, or anywhere in the
//   subtree it roots -- reuses tree.js's own findNode, called with the
//   ancestor's node (rather than the whole tree) as the search root, so no
//   separate subtree-walk needs writing here.
function isWithinSubtree(tree, ancestorId, candidateId) {
  const ancestor = findNode(tree, ancestorId)
  if (!ancestor) return false
  return findNode(ancestor, candidateId) != null
}

// --- placement / limits (advisory) ------------------------------------

// Validates a single-target descriptor (position "before"/"after"/"into"/
// "append") OR, for "chips", re-derives each chip's own valid/reason and
// folds them into one overall valid flag -- the two share every rule
// below (self-descendant, node/depth limits) except that a chip descriptor
// has no one parentId/container of its own to check kind-legality against
// (each chip already carried that from #legalChips, which builds the list
// pre-filtered) or depth against a single parent (each chip's own parentId
// can differ -- navbar's "Left" and "Right" chips are two different
// nodes). Kind-legality for a single-target descriptor is still checked
// here, same as before this file grew a middle band.
function validateTarget(tree, schema, target, draggedKind, draggedNodeId) {
  if (target.position === "chips") {
    const chips = (target.chips || []).map((chip) => ({
      ...chip,
      ...validateSingleTarget(tree, schema, chip, draggedKind, draggedNodeId, { skipKindCheck: true })
    }))
    return { chips, valid: chips.some((chip) => chip.valid), reason: chips.some((chip) => chip.valid) ? null : "nothing here can accept this drop" }
  }

  return validateSingleTarget(tree, schema, target, draggedKind, draggedNodeId, {})
}

function validateSingleTarget(tree, schema, target, draggedKind, draggedNodeId, { skipKindCheck }) {
  // For "wrap", the subtree that actually matters is the node being
  // WRAPPED (tree.js#wrapInRow's own `targetId`), not `target.parentId`
  // (which, for wrap, is wherever the resulting row lands -- the SAME
  // place wrapTargetId already lives, so checking parentId here would
  // only ever catch "dragging a node onto its own current parent", not
  // the real hazard of dragging a node onto its own descendant's edge).
  // "column" has the exact same shape of problem, one node earlier in the
  // chain: the column being JOINED (tree.js#insertColumnBeside's own
  // `columnId`, carried here as `columnTargetId`) is what a dragged node's
  // own subtree must not contain, not `target.parentId` (the ROW the new
  // column lands in, which is further up and not the hazard here).
  const subtreeAnchorId = (() => {
    if (target.position === "wrap") return target.wrapTargetId
    if (target.position === "column") return target.columnTargetId
    return target.parentId
  })()
  if (draggedNodeId && isWithinSubtree(tree, draggedNodeId, subtreeAnchorId)) {
    return { valid: false, reason: "cannot drop a node into its own descendant" }
  }

  const placement = schema && schema.kinds && schema.kinds.placement
  // No schema yet -- nothing to check against. Permissive rather than
  // blocking every drop until the schema fetch resolves (it's requested
  // in #connect and normally back well before a user could start a drag).
  // (A "wrap" descriptor can't even be built without a schema in the first
  // place -- #resolveHorizontalEdge -- so this branch is reachable for one
  // in theory only, never in practice, for "wrap". A "column" descriptor,
  // by contrast, genuinely CAN reach here with no schema loaded --
  // #defaultColumnSpan has its own hardcoded fallback precisely so joining
  // an existing row never has to wait on the schema fetch the way starting
  // a brand-new one does -- so this permissive branch is the real, live
  // answer for an early "column" drag, not just a theoretical one.)
  if (!placement) return { valid: true, reason: null }

  // #legalChips already kind-filtered every chip candidate before this
  // ever runs (see that function) -- re-deriving allowedKindsFor a second
  // time here would just repeat work already done and, for an `items`
  // chip, would ask a question the published placement vocabularies can't
  // answer at all (this file's header). `target.container !== "items"` is
  // the same exemption stated a second way, for the one case that reaches
  // here as a single-target descriptor rather than through the "chips"
  // branch above: #resolveInto's single-candidate branch resolves a lone
  // items chip straight into a plain "into" descriptor (skipKindCheck is
  // only ever true for the PLURAL chips path), so this container check has
  // to recognise "items" on its own too, not just take skipKindCheck's
  // word for it -- #legalChips already vetted it before it was ever the
  // one and only candidate.
  if (!skipKindCheck && target.container !== "items") {
    // A "wrap" drop lands the dragged node inside a freshly created
    // column's own `children`, never at `target.parentId`/`target.container`
    // directly (those describe where the new ROW goes, replacing
    // wrapTargetId) -- a column's children follow the ordinary "non-row
    // container" rule (#allowedKindsFor's own comment: every container
    // except a row's own `children`), so that vocabulary is checked
    // directly here rather than asking #allowedKindsFor a question about
    // a container (the new column) that doesn't exist in the tree yet for
    // it to look up. "column" lands the dragged node in a freshly created
    // column too (tree.js#insertColumnBeside), for exactly the same
    // reason -- `target.container` there is "children" on the EXISTING
    // row, not the new column, so it shares the wrap branch rather than
    // going through #allowedKindsFor.
    const allowedKinds = (target.position === "wrap" || target.position === "column")
      ? (placement.nonRowContainerKinds || [])
      : allowedKindsFor(tree, target.parentId, target.container, placement)
    if (!allowedKinds.includes(draggedKind)) {
      return { valid: false, reason: `a ${draggedKind} cannot be placed there` }
    }
  }

  const limits = schema.limits || {}
  // A "wrap" creates three new nodes unconditionally (the row plus its two
  // columns) on top of whatever the drag itself adds: nothing more for a
  // move (the dragged node already exists, just relocated), one more leaf
  // for a palette drop (tree.js#wrapInRow's `payload.newNode`, built fresh
  // -- see editor_controller.js#_applyWrapDrop). "column" creates only ONE
  // new node (the joining column itself, tree.js#insertColumnBeside) on
  // top of the same drag-itself addition -- the row it joins already
  // exists, unlike wrap's brand-new one.
  let nodeDelta = 1
  if (target.position === "wrap") nodeDelta = draggedNodeId ? 3 : 4
  else if (target.position === "column") nodeDelta = draggedNodeId ? 1 : 2
  if (typeof limits.nodes === "number" && countNodes(tree) + nodeDelta > limits.nodes) {
    return { valid: false, reason: "the design already has the maximum number of nodes" }
  }

  if (typeof limits.depth === "number") {
    const parentDepth = target.parentId === tree.id ? 1 : depthOf(tree, target.parentId)
    // A "wrap" nests three levels deeper than a plain insert at the same
    // parent -- the row (parentDepth + 1), its column (+2), and the node
    // living inside that column (+3) -- rather than landing directly at
    // parentDepth + 1 the way every other position here does. "column"
    // nests two levels deeper than `target.parentId` (the EXISTING row,
    // already counted by `parentDepth`): the new column (+1) and the
    // dragged node living inside it (+2) -- one shallower than wrap
    // because there's no new row level to add here.
    let depthDelta = 1
    if (target.position === "wrap") depthDelta = 3
    else if (target.position === "column") depthDelta = 2
    if (parentDepth != null && parentDepth + depthDelta > limits.depth) {
      return { valid: false, reason: "that spot is nested past the maximum depth" }
    }
  }

  return { valid: true, reason: null }
}

// Mirrors Editor::Tree's own three allowed-kinds lists (ROOT_KINDS /
// NON_ROW_CONTAINER_KINDS / ROW_CONTAINER_KINDS -- see this file's header)
// entirely from the published `placement` vocabularies, never a hardcoded
// copy: the root container gets rootKinds, a `row` node's own "children"
// gets rowContainerKinds (this is the one place `column` is ever legal),
// and every other container (a non-row node's children, any slot, an
// items array) gets nonRowContainerKinds -- exactly Tree's own "everything
// ordinary except column" rule. (An `items` container is a partial
// exception to that last case -- see this file's header -- but every call
// site that resolves one skips this function for it; see
// #legalChips/#validateSingleTarget's `skipKindCheck`.)
function allowedKindsFor(tree, parentId, container, placement) {
  if (parentId === tree.id) return placement.rootKinds || []
  const parentNode = findNode(tree, parentId)
  if (!parentNode) return []
  if (container === "children" && parentNode.kind === "row") return placement.rowContainerKinds || []
  return placement.nonRowContainerKinds || []
}

function countNodes(node) {
  if (!node) return 0
  let total = 1
  if (Array.isArray(node.children)) total += node.children.reduce((sum, child) => sum + countNodes(child), 0)
  if (node.slots && typeof node.slots === "object") {
    total += Object.values(node.slots).reduce((sum, arr) => (
      sum + (Array.isArray(arr) ? arr.reduce((s, child) => s + countNodes(child), 0) : 0)
    ), 0)
  }
  if (Array.isArray(node.items)) total += node.items.reduce((sum, child) => sum + countNodes(child), 0)
  return total
}

// @return the depth (root = 1, same convention Editor::Tree.normalize
//   uses server-side) of the node with `id`, or null if not found.
function depthOf(node, id, depth = 1) {
  if (!node) return null
  if (node.id === id) return depth

  const arrays = []
  if (Array.isArray(node.children)) arrays.push(node.children)
  if (node.slots && typeof node.slots === "object") {
    Object.values(node.slots).forEach((arr) => { if (Array.isArray(arr)) arrays.push(arr) })
  }
  if (Array.isArray(node.items)) arrays.push(node.items)

  for (const arr of arrays) {
    for (const child of arr) {
      const found = depthOf(child, id, depth + 1)
      if (found != null) return found
    }
  }
  return null
}
