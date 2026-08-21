// Stimulus controller for ApexCharts integration
// Automatically initializes ApexCharts from data attributes

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    options: Object,
    type: { type: String, default: "line" },
    height: { type: Number, default: 350 }
  }

  connect() {
    import("apexcharts").then((module) => {
      if (typeof module.default !== "function") {
        console.error("apexcharts loaded but its default export is not a constructor -- the vendored file may be missing its `export default globalThis.ApexCharts` line")
        return
      }

      this.ApexCharts = module.default
      this.initChart()
    }).catch((error) => {
      console.error("Failed to load ApexCharts:", error)
    })
  }

  initChart() {
    if (!this.ApexCharts) {
      console.warn("ApexCharts library not loaded")
      return
    }

    // Merge default options with custom options
    const options = {
      chart: {
        type: this.typeValue,
        height: this.heightValue,
        toolbar: {
          show: false
        }
      },
      ...this.optionsValue
    }

    this.chart = new this.ApexCharts(this.element, options)
    this.chart.render()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  // Allow updating chart data from outside
  updateSeries(newSeries) {
    if (this.chart) {
      this.chart.updateSeries(newSeries)
    }
  }

  // Allow updating chart options from outside
  updateOptions(newOptions, redrawPaths = true, animate = true) {
    if (this.chart) {
      this.chart.updateOptions(newOptions, redrawPaths, animate)
    }
  }
}
