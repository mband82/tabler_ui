/**
 * Tabler UI Gem JavaScript
 *
 * This is main entry point for Tabler UI JavaScript.
 * Import this file in your application to use Tabler UI interactive components.
 *
 * Stimulus controllers are auto-registered via window.Stimulus
 * (set by the host app's controllers/application.js).
 */

import "tabler_ui/tabler"
import "star-rating.js"

// Auto-register Stimulus controllers
import AlertController from "controllers/tabler_ui/alert_controller"
import ChartController from "controllers/tabler_ui/chart_controller"
import CollapseController from "controllers/tabler_ui/collapse_controller"
import DarkModeController from "controllers/tabler_ui/dark_mode_controller"
import DatepickerController from "controllers/tabler_ui/datepicker_controller"
import DropdownMenuController from "controllers/tabler_ui/dropdown_menu_controller"
import FilterController from "controllers/tabler_ui/filter_controller"
import ModalController from "controllers/tabler_ui/modal_controller"
import OffcanvasController from "controllers/tabler_ui/offcanvas_controller"
import ToastController from "controllers/tabler_ui/toast_controller"
import RatingController from "controllers/tabler_ui/rating_controller"
import TabController from "controllers/tabler_ui/tab_controller"
import ToggleButtonController from "controllers/tabler_ui/toggle_button_controller"

if (window.Stimulus) {
  const app = window.Stimulus
  app.register("tabler-ui--alert", AlertController)
  app.register("tabler-ui--chart", ChartController)
  app.register("tabler-ui--collapse", CollapseController)
  app.register("tabler-ui--dark-mode", DarkModeController)
  app.register("tabler-ui--datepicker", DatepickerController)
  app.register("tabler-ui--dropdown-menu", DropdownMenuController)
  app.register("tabler-ui--filter", FilterController)
  app.register("tabler-ui--modal", ModalController)
  app.register("tabler-ui--offcanvas", OffcanvasController)
  app.register("tabler-ui--toast", ToastController)
  app.register("tabler-ui--rating", RatingController)
  app.register("tabler-ui--tab", TabController)
  app.register("tabler-ui--toggle-button", ToggleButtonController)
}
