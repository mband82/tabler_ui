# frozen_string_literal: true

require "rails_helper"

# TablerUi.auth_method is global, process-wide mutable state -- restore it
# after every example so a custom auth_method here never leaks into specs
# that run afterward (see ui_spec.rb's identical around block for the same
# reasoning).
RSpec.describe TablerUi::Authorization do
  around do |example|
    original = TablerUi.auth_method
    example.run
    TablerUi.auth_method = original
  end

  describe ".authorized?" do
    it "is true for any value under the default auth_method" do
      expect(described_class.authorized?(nil)).to be(true)
      expect(described_class.authorized?(:manage_users)).to be(true)
      expect(described_class.authorized?(false)).to be(true)
    end

    it "reflects a custom auth_method returning true" do
      TablerUi.auth_method = ->(_value) { true }

      expect(described_class.authorized?(:anything)).to be(true)
    end

    it "reflects a custom auth_method returning false" do
      TablerUi.auth_method = ->(_value) { false }

      expect(described_class.authorized?(:anything)).to be(false)
    end

    it "coerces a truthy non-boolean return to true" do
      TablerUi.auth_method = ->(_value) { "yes" }

      expect(described_class.authorized?(:anything)).to be(true)
    end

    it "coerces a falsy nil return to false" do
      TablerUi.auth_method = ->(_value) { nil }

      expect(described_class.authorized?(:anything)).to be(false)
    end

    it "passes the argument through unchanged" do
      received = []
      TablerUi.auth_method = ->(value) { received << value; true }

      described_class.authorized?(:manage_users)
      described_class.authorized?(nil)
      described_class.authorized?(42)

      expect(received).to eq([:manage_users, nil, 42])
    end
  end
end
