// Stimulus controller for vanillajs-datepicker integration. Instantiates a
// single-date or range picker (based on the element's tag) with min/max/
// format options on connect, and destroys it on disconnect.
import {Controller} from "@hotwired/stimulus"
import "vanillajs-datepicker";

export default class extends Controller {
    static values = {
        min: { type: String, default: null },
        max: { type: String, default: null },
        format: { type: String, default: "yyyy-mm-dd" }
    }

    connect() {
        // vanillajs-datepicker is pinned to a CDN -- guard against it
        // failing to load rather than throwing.
        if (typeof Datepicker === "undefined") return

        const options = {
            buttonClass: 'btn',
            autohide: true,
            format: this.formatValue,
            minDate: this.minValue ? new Date(this.minValue) : null,
            maxDate: this.maxValue ? new Date(this.maxValue) : null,
            weekNumbers: 1,
            weekStart: 1
        }

        this.picker = this.element.tagName === "INPUT"
            ? new Datepicker(this.element, options)
            : new DateRangePicker(this.element, options)
    }

    disconnect() {
        if (this.picker) {
            this.picker.destroy()
            this.picker = null
        }
    }
}
