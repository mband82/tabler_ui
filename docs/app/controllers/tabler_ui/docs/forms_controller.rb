# frozen_string_literal: true

module TablerUi
  module Docs
    # Forms harness page: GET /ui/forms (see config/routes.rb). Ported from
    # showcase/app/views/showcase/forms.html.erb + ShowcaseController#forms.
    #
    # Wraps every TablerUi::FormBuilder field-level demo
    # (docs/lib/tabler_ui/docs/demos/form_builder_demos.rb) in one real
    # tabler_form_with around a single TablerUi::Docs::PersonForm, so
    # f.error_notification and inline field errors behave exactly as they
    # would in a host app. This is deliberately separate from the generic
    # `/ui/demos/:component` route (DemosController#show): that one renders
    # each demo's source in total isolation, via the throwaway `f` each
    # form_builder demo's own `locals:` proc builds for itself -- see
    # form_builder_demos.rb and docs/app/views/tabler_ui/docs/demos/_form_demo.html.erb.
    class FormsController < ApplicationController
      def show
        # form_builder has no app/components/tabler_ui directory (see
        # Navigation::FORM_BUILDER's own comment), so it gets its own
        # top-level sidebar entry rather than one inside CATEGORIES -- this
        # is how that entry gets marked active on its own page.
        @nav_current = Navigation::FORM_BUILDER
        @person = PersonForm.sample(with_errors: params[:with_errors].present?)
      end
    end
  end
end
