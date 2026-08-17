# frozen_string_literal: true

Rails.application.routes.draw do
  root "showcase#index"

  get "layout", to: "showcase#layout"
  get "content", to: "showcase#content"
  get "overlays", to: "showcase#overlays"
  get "forms", to: "showcase#forms"
end
