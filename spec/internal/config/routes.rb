Rails.application.routes.draw do
  mount TablerUi::Docs::Engine => "/ui"
end
