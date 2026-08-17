# frozen_string_literal: true

require "rails_helper"
require "active_model"

# There is no ActiveRecord in this harness (see spec/rails_helper.rb), so
# FormBuilder#object_type_for_method's data source is faked with a plain
# Ruby class that quacks like a model: it implements exactly what that
# method calls (type_for_attribute / has_attribute? / column_for_attribute),
# plus #errors and attribute readers/writers, via method_missing. A plain
# double was chosen over ActiveModel::Model because even with ActiveModel
# included there would still be no database to derive column types from --
# the type-faking is unavoidable either way, so the plain double keeps the
# surface limited to exactly what FormBuilder touches.
class FakeErrors
  def initialize(messages = {})
    @messages = messages.transform_keys(&:to_sym).transform_values { |v| Array(v) }
  end

  def key?(attribute)
    @messages[attribute.to_sym].present?
  end
  alias include? key?

  def [](attribute)
    @messages[attribute.to_sym] || []
  end

  def any?
    @messages.values.any?(&:any?)
  end

  def full_messages
    @messages.flat_map do |attribute, msgs|
      msgs.map { |msg| "#{attribute.to_s.humanize} #{msg}" }
    end
  end
end

class FakeModel
  Type = Struct.new(:type)

  def initialize(attributes = {}, types: {}, errors: {})
    @attributes = attributes.transform_keys(&:to_sym)
    @types = types.transform_keys(&:to_sym)
    @errors = FakeErrors.new(errors)
  end

  attr_reader :errors

  def has_attribute?(name)
    @types.key?(name.to_sym)
  end

  def type_for_attribute(name)
    type = @types[name.to_sym]
    Type.new(type) if type
  end

  def column_for_attribute(name)
    type_for_attribute(name)
  end

  def method_missing(name, *args)
    key = name.to_s.chomp("=").to_sym
    if name.to_s.end_with?("=") && @attributes.key?(key)
      @attributes[key] = args.first
    elsif @attributes.key?(key)
      @attributes[key]
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    @attributes.key?(name.to_s.chomp("=").to_sym) || super
  end
end

# A real ActiveModel::Model + ActiveModel::Attributes object, used to prove
# that #object_type_for_method's automatic type dispatch also works for
# non-ActiveRecord models. Rails' ActiveModel::Attributes module defines
# `type_for_attribute`/`attribute_types` on the *class*, not the instance,
# and defines no `has_attribute?` at all -- unlike ActiveRecord's equivalents,
# which are instance methods. FakeModel above hand-rolls exactly that
# instance-level ActiveRecord-shaped surface, so it can't exercise this path;
# only Rails' own module, included for real, demonstrates how it actually
# exposes types.
class ActiveModelAttributesFakeModel
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :quantity, :integer
  attribute :price, :decimal
  attribute :starts_at, :datetime
  attribute :born_on, :date
end

RSpec.describe TablerUi::FormBuilder do
  # A real ActionView::Base view context, built the same way
  # spec/support/component_helper.rb does it, since FormBuilder's input
  # methods (text_field, number_field, ...) are template helper methods
  # that need a real template object, not a double.
  def form_builder_view_context
    @form_builder_view_context ||= begin
      view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
      view_class = ActionView::Base.with_empty_template_cache
      view_class.include(TablerUi::Helper)
      view_class.with_view_paths(view_paths, {})
    end
  end

  def build_form(model)
    described_class.new("model", model, form_builder_view_context, {})
  end

  def fragment_for(html)
    Nokogiri::HTML5.fragment(html)
  end

  describe "#input dispatch on column type" do
    it "renders a number field for a :decimal column instead of raising (regression)" do
      model = FakeModel.new({ price: "19.99" }, types: { price: :decimal })
      form = build_form(model)

      expect { fragment_for(form.input(:price)) }.not_to raise_error

      field = fragment_for(form.input(:price)).css('input[name="model[price]"]').first
      expect(field["type"]).to eq("number")
      expect(field["step"]).to eq("any")
    end

    it "renders a number field for a :float column" do
      model = FakeModel.new({ ratio: "0.5" }, types: { ratio: :float })
      form = build_form(model)

      fragment = fragment_for(form.input(:ratio))
      field = fragment.css('input[name="model[ratio]"]').first

      expect(field["type"]).to eq("number")
      expect(field["step"]).to eq("any")
    end

    it "renders a datetime-local field for a :datetime column" do
      model = FakeModel.new({ starts_at: nil }, types: { starts_at: :datetime })
      form = build_form(model)

      fragment = fragment_for(form.input(:starts_at))
      field = fragment.css('input[name="model[starts_at]"]').first

      expect(field["type"]).to eq("datetime-local")
    end

    it "renders a time field for a :time column" do
      model = FakeModel.new({ opens_at: nil }, types: { opens_at: :time })
      form = build_form(model)

      fragment = fragment_for(form.input(:opens_at))
      field = fragment.css('input[name="model[opens_at]"]').first

      expect(field["type"]).to eq("time")
    end

    it "still renders a plain text field for a :string column" do
      model = FakeModel.new({ name: "Ada" }, types: { name: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:name))
      field = fragment.css('input[name="model[name]"]').first

      expect(field["type"]).to eq("text")
      expect(field["value"]).to eq("Ada")
    end

    it "still renders a textarea for a :text column" do
      model = FakeModel.new({ bio: "hello" }, types: { bio: :text })
      form = build_form(model)

      fragment = fragment_for(form.input(:bio))

      expect(fragment.css('textarea[name="model[bio]"]')).not_to be_empty
    end

    it "still renders a number field with no forced step for an :integer column" do
      model = FakeModel.new({ age: 5 }, types: { age: :integer })
      form = build_form(model)

      fragment = fragment_for(form.input(:age))
      field = fragment.css('input[name="model[age]"]').first

      expect(field["type"]).to eq("number")
      expect(field["step"]).to be_nil
    end

    it "still renders a checkbox for a :boolean column" do
      model = FakeModel.new({ active: true }, types: { active: :boolean })
      form = build_form(model)

      fragment = fragment_for(form.input(:active))

      expect(fragment.css('input[type="checkbox"][name="model[active]"]')).not_to be_empty
    end

    it "still routes a :date column through the tabler-ui--datepicker controller" do
      model = FakeModel.new({ born_on: nil }, types: { born_on: :date })
      form = build_form(model)

      fragment = fragment_for(form.input(:born_on))
      field = fragment.css('input[name="model[born_on]"]').first

      expect(field["type"]).to eq("text")
      expect(field["data-controller"]).to eq("tabler-ui--datepicker")
    end

    it "still renders a select for as: :select with a collection" do
      model = FakeModel.new({ role: "admin" }, types: { role: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:role, as: :select, collection: %w[admin member]))

      expect(fragment.css('select[name="model[role]"]')).not_to be_empty
      expect(fragment.css("option").map(&:text)).to include("admin", "member")
    end

    it "still renders a file field for as: :file" do
      model = FakeModel.new({ avatar: nil }, types: { avatar: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:avatar, as: :file))

      expect(fragment.css('input[type="file"][name="model[avatar]"]')).not_to be_empty
    end

    it "still renders a bare hidden field with no wrapper for as: :hidden" do
      model = FakeModel.new({ token: "abc" }, types: { token: :string })
      form = build_form(model)

      html = form.input(:token, as: :hidden)
      fragment = fragment_for(html)

      expect(fragment.css('input[type="hidden"][name="model[token]"]')).not_to be_empty
      expect(fragment.css("div.mb-3")).to be_empty
    end

    it "raises a clear error naming the field and type for a genuinely unknown column type, not NoMethodError" do
      model = FakeModel.new({ balance: nil }, types: { balance: :money })
      form = build_form(model)

      expect { form.input(:balance) }.to raise_error(ArgumentError) do |error|
        expect(error).not_to be_a(NoMethodError)
        expect(error.message).to include("balance")
        expect(error.message).to include("money")
      end
    end
  end

  describe "#input dispatch on ActiveModel::Attributes (non-ActiveRecord) objects" do
    it "renders a number field for an :integer attribute instead of falling back to text (regression)" do
      model = ActiveModelAttributesFakeModel.new(quantity: 5)
      form = build_form(model)

      field = fragment_for(form.input(:quantity)).css('input[name="model[quantity]"]').first

      expect(field["type"]).to eq("number")
    end

    it "renders a number field with step=any for a :decimal attribute instead of falling back to text (regression)" do
      model = ActiveModelAttributesFakeModel.new(price: "19.99")
      form = build_form(model)

      field = fragment_for(form.input(:price)).css('input[name="model[price]"]').first

      expect(field["type"]).to eq("number")
      expect(field["step"]).to eq("any")
    end

    it "renders a datetime-local field for a :datetime attribute instead of falling back to text (regression)" do
      model = ActiveModelAttributesFakeModel.new(starts_at: nil)
      form = build_form(model)

      field = fragment_for(form.input(:starts_at)).css('input[name="model[starts_at]"]').first

      expect(field["type"]).to eq("datetime-local")
    end

    it "routes a :date attribute through the tabler-ui--datepicker controller instead of falling back to text (regression)" do
      model = ActiveModelAttributesFakeModel.new(born_on: nil)
      form = build_form(model)

      field = fragment_for(form.input(:born_on)).css('input[name="model[born_on]"]').first

      expect(field["type"]).to eq("text")
      expect(field["data-controller"]).to eq("tabler-ui--datepicker")
    end
  end

  describe "as: :input_group" do
    it "renders an input group instead of raising (regression)" do
      model = FakeModel.new({ amount: "10" }, types: { amount: :string })
      form = build_form(model)

      expect { form.input(:amount, as: :input_group) }.not_to raise_error

      fragment = fragment_for(form.input(:amount, as: :input_group))
      expect(fragment.css("div.input-group")).not_to be_empty
      expect(fragment.css('input[name="model[amount]"]')).not_to be_empty
    end

    it "renders prepend and append text" do
      model = FakeModel.new({ amount: "10" }, types: { amount: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:amount, as: :input_group, prepend: "$", append: ".00"))
      texts = fragment.css("div.input-group .input-group-text").map(&:text)

      expect(texts).to eq(%w[$ .00])
    end
  end

  describe "input_html: merging (rule 5 contract via merge_input_options)" do
    it "appends the caller's class to the component's own form-control class rather than replacing it" do
      model = FakeModel.new({ name: "Ada" }, types: { name: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:name, input_html: { class: "hook-extra-class" }))
      classes = fragment.css('input[name="model[name]"]').first["class"].split(/\s+/)

      expect(classes).to include("form-control", "hook-extra-class")
    end

    it "passes through other input_html attributes such as data-* and id" do
      model = FakeModel.new({ name: "Ada" }, types: { name: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:name, input_html: { id: "custom-id", data: { testid: "name-field" } }))
      field = fragment.css('input[name="model[name]"]').first

      expect(field["id"]).to eq("custom-id")
      expect(field["data-testid"]).to eq("name-field")
    end
  end

  describe "error state" do
    it "marks a field with errors as is-invalid and renders the message" do
      model = FakeModel.new({ name: "" }, types: { name: :string }, errors: { name: ["can't be blank"] })
      form = build_form(model)

      fragment = fragment_for(form.input(:name))
      field = fragment.css('input[name="model[name]"]').first

      expect(field["class"].split(/\s+/)).to include("is-invalid")
      expect(fragment.css(".invalid-feedback").text).to include("can't be blank")
    end

    it "does not mark a field without errors as is-invalid" do
      model = FakeModel.new({ name: "Ada" }, types: { name: :string })
      form = build_form(model)

      fragment = fragment_for(form.input(:name))
      field = fragment.css('input[name="model[name]"]').first

      expect(field["class"].split(/\s+/)).not_to include("is-invalid")
      expect(fragment.css(".invalid-feedback")).to be_empty
    end
  end

  describe "#error_notification" do
    it "renders the model's full error messages" do
      model = FakeModel.new(
        { name: "", price: nil },
        types: { name: :string, price: :decimal },
        errors: { name: ["can't be blank"], price: ["is not a number"] }
      )
      form = build_form(model)

      fragment = fragment_for(form.error_notification)

      expect(fragment.css(".alert.alert-danger")).not_to be_empty
      messages = fragment.css("li").map(&:text)
      expect(messages).to include("Name can't be blank", "Price is not a number")
    end

    it "renders nothing when the model has no errors" do
      model = FakeModel.new({ name: "Ada" }, types: { name: :string })
      form = build_form(model)

      expect(form.error_notification).to be_nil
    end
  end
end
