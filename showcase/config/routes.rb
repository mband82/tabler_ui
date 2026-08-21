# frozen_string_literal: true

Rails.application.routes.draw do
  mount TablerUi::Docs::Engine, at: "/"
end
