import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false

// tabler_ui.js self-registers its Stimulus controllers only inside
// `if (window.Stimulus)`, so this assignment MUST happen -- and this module
// MUST finish executing -- before `import "tabler_ui"` runs. ES module
// imports execute depth-first in source order, so application.js (the entry
// point) imports this file first and "tabler_ui" second.
window.Stimulus = application

export { application }
