# frozen_string_literal: true

# Not a dependency this gem loads for its own app/lib code (see CLAUDE.md's
# Architecture brief -- ActiveRecord is intentionally left out of the specs,
# and nothing else here needs ActiveModel either), so it isn't required
# anywhere Zeitwerk would have hit it already by the time this file
# autoloads. spec/lib/tabler_ui/form_builder_spec.rb requires it the same
# way, at the top of the file that first needs it.
require "active_model"

module TablerUi
  module Docs
    # A plain ActiveModel double -- no database -- backing the forms harness
    # page (docs/app/controllers/tabler_ui/docs/forms_controller.rb +
    # docs/app/views/tabler_ui/docs/forms/show.html.erb) and every standalone
    # demo in docs/lib/tabler_ui/docs/demos/form_builder_demos.rb.
    #
    # Moved here from showcase/app/controllers/showcase_controller.rb (it was
    # a class nested inside ShowcaseController there) rather than rewritten:
    # same 19 attributes, same single presence validation.
    #
    # NOTE: TablerUi::FormBuilder#object_type_for_method infers a field's
    # widget from @object.type_for_attribute / #has_attribute?, both
    # ActiveRecord *instance* methods. ActiveModel::Attributes only defines
    # type_for_attribute/attribute_types at the CLASS level (see
    # ActiveModel::AttributeRegistration::ClassMethods) and defines no
    # has_attribute? at all -- so on a plain ActiveModel::Model instance like
    # this one, both of those instance-level checks are false/skipped.
    #
    # The showcase's original version of this comment stopped there and
    # concluded every field "silently falls back to a plain text input",
    # leaving appointment_at/salary without an `as:` "to demonstrate the
    # gap". That conclusion is WRONG: object_type_for_method has a third
    # branch for exactly this case -- when the instance exposes neither
    # instance method, it falls back to `@object.class.attribute_types`,
    # which ActiveModel::Attributes DOES define at the class level (see
    # lib/tabler_ui/form_builder.rb, the third `elsif` in
    # #object_type_for_method). Verified empirically by rendering both
    # fields (see the :inferred_types demo in form_builder_demos.rb and
    # spec/requests/tabler_ui/docs/forms_spec.rb): appointment_at
    # (:datetime) renders a native <input type="datetime-local"> and salary
    # (:decimal) renders <input type="number" step="any">, no `as:` needed
    # -- exactly as it would for an ActiveRecord-backed object. This matches
    # spec/lib/tabler_ui/form_builder_spec.rb's own "#input dispatch on
    # ActiveModel::Attributes (non-ActiveRecord) objects" regression group.
    class PersonForm
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :name, :string
      attribute :email, :string
      attribute :bio, :string
      attribute :birthday, :date
      attribute :appointment_at, :datetime
      attribute :salary, :decimal
      attribute :website, :string
      attribute :phone, :string
      attribute :newsletter, :boolean
      attribute :bio_notifications, :boolean
      attribute :plan, :string
      attribute :role, :string
      attribute :team, :string
      attribute :interests, default: -> { [] }
      attribute :color, :string
      attribute :theme, :string
      attribute :avatar_rating, :integer
      attribute :manager_id, :string
      attribute :resume
      attribute :search_query, :string

      validates :name, presence: true

      # A single, fully-populated instance -- the same field values the old
      # showcase's ShowcaseController#forms action built inline. Shared by
      # the forms harness controller and by every form_builder_demos.rb
      # demo's `locals:` fallback (see FormBuilderDemoFixture below), so
      # both consumers show the same realistic data.
      #
      # @param with_errors [Boolean] when true, runs validation and forces
      #   an extra :email error -- mirrors ?with_errors=1 on the old
      #   showcase, which forced the same error the same way.
      # @return [PersonForm]
      def self.sample(with_errors: false)
        person = new(
          name: "Ada Lovelace",
          email: "ada@example.com",
          bio: "Mathematician and writer, chiefly known for her work on Charles Babbage's Analytical Engine.",
          birthday: Date.new(1815, 12, 10),
          appointment_at: Time.zone.local(2026, 9, 1, 14, 30),
          salary: 1234.56,
          website: "https://example.com",
          phone: "+1 555 0100",
          newsletter: true,
          bio_notifications: true,
          plan: "pro",
          role: "admin",
          team: "backend",
          interests: ["Engineering"],
          color: "#4299e1",
          theme: "blue",
          avatar_rating: 4,
          manager_id: "Alice",
          resume: nil,
          search_query: nil
        )
        person.valid?
        person.errors.add(:email, "is already taken") if with_errors
        person
      end
    end
  end
end
