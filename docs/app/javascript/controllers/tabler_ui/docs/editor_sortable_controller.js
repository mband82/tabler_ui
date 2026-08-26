// Generic drag-and-drop reordering for the design editor's Structure and
// Explorer panes -- a purely additive enhancement layered on top of the
// existing move-up/move-down/delete buttons those panes already render
// (editor/structure.js, editor/explorer.js). Those buttons remain the real
// mechanism (a host with a strict CSP will never load SortableJS from its
// CDN pin, "tabler_ui/docs/sortable" in docs/config/importmap.rb); this
// controller only ever adds a second way to do the same mutation.
//
// One instance of this controller is attached to EVERY container element
// that should be independently sortable -- see structure.js/explorer.js,
// which stamp `data-controller="tabler-ui--docs-editor-sortable"` onto
// each array-backed container they render (root children, each node's own
// children/items/slot arrays; each directory's file list). Stimulus
// instantiates and tears down each nested instance on its own, which is
// exactly why this lives as a separate controller rather than as methods
// on the main tabler-ui--docs-editor controller -- one Sortable instance
// per container, not one for the whole tree.
//
// This controller knows nothing about design-tree nodes, workspace files,
// or the editor's own data model -- only generic DOM containers/items
// identified by data attributes (data-editor-container-id,
// data-editor-item-id). It reports what happened via a bubbling
// "tabler-ui--docs-editor-sortable:move" CustomEvent and lets the main
// editor controller (editor_controller.js#handleSortableMove) decide what
// the move means and how to mutate the tree/workspace.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    // "structure" or "explorer" -- passed straight through as SortableJS's
    // own `group` option, so a structure-outline container only ever
    // accepts drops from another structure-outline container, and an
    // explorer container only from another explorer container. No
    // cross-pane drags are possible.
    group: { type: String, default: "" }
  }

  connect() {
    this.sortable = null

    // Dynamic import, guarded the same way app/javascript/controllers/
    // tabler_ui/chart_controller.js guards ApexCharts: a CDN load failure
    // (offline dev, a strict-CSP host) must never throw here -- the
    // buttons structure.js/explorer.js already render are the real
    // mechanism, this is only ever a bonus on top of them.
    import("tabler_ui/docs/sortable")
      .then((module) => this._initSortable(module))
      .catch((error) => {
        console.error("Failed to load SortableJS -- drag-and-drop reordering is disabled, the existing move/delete buttons still work:", error)
      })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  _initSortable(module) {
    // The controller was disconnected (e.g. a structural change re-rendered
    // the Structure/Explorer pane) before the import resolved -- nothing to
    // attach to any more.
    if (!this.element.isConnected) return

    // jsDelivr's modular ESM build exports the Sortable class as `default`;
    // fall back to a `window.Sortable` global in case a differently-shaped
    // build ever ends up behind this pin.
    const Sortable = (typeof module.default === "function") ? module.default : window.Sortable
    if (typeof Sortable !== "function") {
      console.error("tabler_ui/docs/sortable loaded but exposed no usable Sortable constructor -- drag-and-drop reordering is disabled")
      return
    }

    this.sortable = new Sortable(this.element, {
      group: this.groupValue || undefined,
      animation: 150,
      ghostClass: "docs-editor-sortable-ghost",
      chosenClass: "docs-editor-sortable-chosen",
      dragClass: "docs-editor-sortable-drag",
      // Excludes non-draggable pseudo-rows (e.g. an empty slot's
      // placeholder row in structure.js) -- only a real item's own element
      // carries data-editor-item-id. That element is the node's wrapper div
      // in structure.js (so a drag carries the node's whole subtree) and
      // the row itself in explorer.js.
      draggable: "[data-editor-item-id]",
      onEnd: (evt) => this._handleEnd(evt)
    })
  }

  _handleEnd(evt) {
    this.dispatch("move", {
      bubbles: true,
      detail: {
        itemId: evt.item.dataset.editorItemId,
        fromContainer: evt.from.dataset.editorContainerId,
        toContainer: evt.to.dataset.editorContainerId,
        oldIndex: evt.oldIndex,
        newIndex: evt.newIndex
      }
    })
  }
}
