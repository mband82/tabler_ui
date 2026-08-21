// Stimulus controller for the light/dark/system theme switcher. Persists the
// chosen theme to localStorage, tracks the OS-level preference while "system"
// is selected, and toggles data-bs-theme plus the light/dark/system icon
// targets to match.
//
// toggle() re-reads localStorage on every call rather than trusting a cached
// `this.theme` across the whole controller lifecycle. Turbo Drive intercepts
// *any* <a href> click -- including one that only changes the URL fragment --
// and turns it into a real visit (a fetch back to the same page, followed by
// a full DOM swap), which disconnects and reconnects every controller on the
// page. The trigger element is a <button> now precisely to avoid that, but
// this controller no longer assumes it is the only thing that can ever touch
// the toggle (another instance of it elsewhere on the page, a future
// reconnect from some other cause) -- localStorage stays the single source
// of truth and `this.theme` is only ever a same-tick cache of it.
import {Controller} from "@hotwired/stimulus"

const THEMES = ["light", "dark", "system"]
const NEXT_THEME = {light: "dark", dark: "system", system: "light"}

export default class extends Controller {
    static targets = ["light", "dark", "system"]

    connect() {
        this.theme = this.readTheme()
        localStorage.setItem("theme", this.theme)

        // Listen for system preference changes
        this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
        this.handleSystemChange = this.handleSystemChange.bind(this)
        this.mediaQuery.addEventListener('change', this.handleSystemChange)

        this.updateTheme()
        this.updateIcon()
    }

    disconnect() {
        if (this.mediaQuery) {
            this.mediaQuery.removeEventListener('change', this.handleSystemChange)
        }
    }

    toggle() {
        // Source of truth is localStorage, not this.theme -- see file header.
        this.theme = NEXT_THEME[this.readTheme()]
        localStorage.setItem("theme", this.theme)

        this.updateTheme()
        this.updateIcon()
    }

    handleSystemChange(event) {
        if (this.readTheme() === "system") {
            this.updateTheme()
        }
    }

    readTheme() {
        const stored = localStorage.getItem("theme")
        return THEMES.includes(stored) ? stored : "system"
    }

    updateIcon() {
        if (this.hasLightTarget) {
            this.lightTarget.classList.toggle("d-none", this.theme !== "light")
        }
        if (this.hasDarkTarget) {
            this.darkTarget.classList.toggle("d-none", this.theme !== "dark")
        }
        if (this.hasSystemTarget) {
            this.systemTarget.classList.toggle("d-none", this.theme !== "system")
        }
    }

    updateTheme() {
        let isDark = false

        if (this.theme === "dark") {
            isDark = true
        } else if (this.theme === "system") {
            isDark = this.mediaQuery.matches
        }

        const theme = isDark ? "dark" : "light"
        document.documentElement.setAttribute("data-bs-theme", theme)
        document.body.setAttribute("data-bs-theme", theme)
    }
}
