# Tabler UI Importmap Configuration
# This file is automatically loaded by Rails when the gem is used
# Stimulus is pinned by the host app, not here

# Pin Tabler UI JavaScript
pin 'tabler_ui', to: 'tabler_ui.js'
pin 'tabler_ui/tabler', to: 'tabler_ui/tabler.js'

# Pin external dependencies
pin 'vanillajs-datepicker', to: 'https://cdn.jsdelivr.net/npm/vanillajs-datepicker@1.3.4/dist/js/datepicker-full.min.js'

# Pin star-rating.js (bundled with gem)
pin 'star-rating.js', to: 'star-rating.js'

# Pin ApexCharts (bundled with gem)
pin 'apexcharts', to: 'apexcharts.js'

# Pin Tabler UI Stimulus controllers
pin 'controllers/tabler_ui/alert_controller', to: 'controllers/tabler_ui/alert_controller.js'
pin 'controllers/tabler_ui/chart_controller', to: 'controllers/tabler_ui/chart_controller.js'
pin 'controllers/tabler_ui/collapse_controller', to: 'controllers/tabler_ui/collapse_controller.js'
pin 'controllers/tabler_ui/dark_mode_controller', to: 'controllers/tabler_ui/dark_mode_controller.js'
pin 'controllers/tabler_ui/datepicker_controller', to: 'controllers/tabler_ui/datepicker_controller.js'
pin 'controllers/tabler_ui/dropdown_menu_controller', to: 'controllers/tabler_ui/dropdown_menu_controller.js'
pin 'controllers/tabler_ui/filter_controller', to: 'controllers/tabler_ui/filter_controller.js'
pin 'controllers/tabler_ui/rating_controller', to: 'controllers/tabler_ui/rating_controller.js'
pin 'controllers/tabler_ui/tab_controller', to: 'controllers/tabler_ui/tab_controller.js'
pin 'controllers/tabler_ui/toggle_button_controller', to: 'controllers/tabler_ui/toggle_button_controller.js'
