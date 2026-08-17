# frozen_string_literal: true

module TablerUi
  class Engine < ::Rails::Engine
    isolate_namespace TablerUi

    config.autoload_paths << root.join('app/components')

    initializer 'tabler_ui.assets' do |app|
      app.config.assets.paths << root.join('app/assets/stylesheets')
      app.config.assets.paths << root.join('app/assets/javascripts')
      app.config.assets.paths << root.join('app/assets/images')
      app.config.assets.paths << root.join('app/javascript')
      app.config.assets.precompile += %w[
        tabler_ui.css tabler_ui.js
        tabler_ui/tabler.css tabler_ui/tabler.js
        tabler_ui/tabler-theme.js
        tabler_ui/datepicker.css
        tabler_ui/navbar.css
        star-rating.css star-rating.js
        apexcharts.css apexcharts.js
        tabler_ui/addons/*.css
        tabler_ui/flags/**/*.svg
        controllers/tabler_ui/alert_controller.js
        controllers/tabler_ui/chart_controller.js
        controllers/tabler_ui/collapse_controller.js
        controllers/tabler_ui/dark_mode_controller.js
        controllers/tabler_ui/datepicker_controller.js
        controllers/tabler_ui/dropdown_menu_controller.js
        controllers/tabler_ui/filter_controller.js
        controllers/tabler_ui/modal_controller.js
        controllers/tabler_ui/offcanvas_controller.js
        controllers/tabler_ui/toast_controller.js
        controllers/tabler_ui/carousel_controller.js
        controllers/tabler_ui/rating_controller.js
        controllers/tabler_ui/tab_controller.js
        controllers/tabler_ui/toggle_button_controller.js
      ]
    end

    # Load importmap configuration for JavaScript modules
    initializer 'tabler_ui.importmap', before: 'importmap' do |app|
      app.config.importmap.paths << root.join('config/importmap.rb') if app.config.respond_to?(:importmap)
    end

    initializer 'tabler_ui.view_paths' do
      ActiveSupport.on_load(:action_controller_base) do
        prepend_view_path(TablerUi::Engine.root.join('app/components'))
      end

      ActiveSupport.on_load(:action_mailer) do
        prepend_view_path(TablerUi::Engine.root.join('app/components'))
      end
    end

    initializer 'tabler_ui.helpers' do
      ActiveSupport.on_load(:action_controller_base) do
        helper TablerUi::Helper
      end

      ActiveSupport.on_load(:action_mailer) do
        helper TablerUi::Helper
      end
    end
  end
end
