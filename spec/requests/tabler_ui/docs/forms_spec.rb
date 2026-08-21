# frozen_string_literal: true

require "rails_helper"

# The forms harness page: GET /ui/forms (spec/internal/config/routes.rb
# mounts TablerUi::Docs::Engine at "/ui", docs/config/routes.rb maps
# "forms" -> FormsController#show, see spec/lib/tabler_ui/docs/engine_spec.rb
# for the same pattern against a different page).
#
# Unlike the generic /ui/demos/:component route, this page wraps every
# form_builder_demos.rb demo in one real tabler_form_with around a single
# TablerUi::Docs::PersonForm (docs/app/models/tabler_ui/docs/person_form.rb)
# -- see docs/app/views/tabler_ui/docs/forms/show.html.erb and
# docs/app/views/tabler_ui/docs/demos/_form_demo.html.erb. This spec checks
# what the registry's generic "every demo renders" spec cannot: that the
# real page renders 200, that each FormBuilder input type emits the expected
# element/type against the real request-bound @person, and that the
# ?with_errors=1 error state actually shows the error banner --
# FormBuilder#error_notification delegates to the alert component
# (lib/tabler_ui/form_builder.rb#error_notification), so this also proves
# that delegation still renders correctly end to end.
RSpec.describe "TablerUi::Docs Forms harness", type: :request do
  def field(name)
    Nokogiri::HTML5.fragment(response.body).at_css(%([name="person[#{name}]"]))
  end

  describe "GET /ui/forms" do
    before { get "/ui/forms" }

    it "renders 200" do
      expect(response).to have_http_status(:ok)
    end

    it "renders a real <form> wrapping the fields (the harness, not a standalone fragment)" do
      expect(Nokogiri::HTML5.fragment(response.body).at_css("form")).not_to be_nil
    end

    it "f.input :name -- default :string renders a text input" do
      expect(field("name")["type"]).to eq("text")
      expect(field("name")["value"]).to eq("Ada Lovelace")
    end

    it "f.input :email -- name-pattern email_field renders an email input" do
      expect(field("email")["type"]).to eq("email")
    end

    it "f.input :bio, as: :text renders a textarea" do
      expect(field("bio").name).to eq("textarea")
    end

    it "f.input :birthday, as: :date_picker renders a text input wired to the datepicker controller" do
      expect(field("birthday")["type"]).to eq("text")
      expect(field("birthday")["data-controller"]).to eq("tabler-ui--datepicker")
    end

    it "f.input :phone -- name-pattern telephone_field renders a tel input" do
      expect(field("phone")["type"]).to eq("tel")
    end

    it "f.toggle_switch :newsletter renders a checkbox (ignoring Rails' own hidden unchecked-value companion)" do
      checkbox = Nokogiri::HTML5.fragment(response.body).at_css('input[type="checkbox"][name="person[newsletter]"]')
      expect(checkbox).not_to be_nil
    end

    it "f.toggle_button :bio_notifications renders a button, not a plain checkbox" do
      html = Nokogiri::HTML5.fragment(response.body)
      expect(html.css("button.btn-success, button.btn-outline-success")).not_to be_empty
    end

    it "f.input :plan, as: :radio_buttons renders radio inputs" do
      html = Nokogiri::HTML5.fragment(response.body)
      radios = html.css('input[type="radio"][name="person[plan]"]')
      expect(radios.size).to eq(3)
    end

    it "f.input :interests, as: :check_boxes renders checkbox inputs" do
      html = Nokogiri::HTML5.fragment(response.body)
      boxes = html.css('input[type="checkbox"][name="person[interests][]"]')
      expect(boxes).not_to be_empty
      expect(boxes.map { |b| b["type"] }.uniq).to eq(["checkbox"])
    end

    it "f.input :role, as: :select renders a select" do
      expect(field("role").name).to eq("select")
    end

    it "f.input :team, as: :grouped_select renders a select with optgroups" do
      select = field("team")
      expect(select.name).to eq("select")
      expect(select.css("optgroup").map { |g| g["label"] }).to eq(%w[Engineering Product])
    end

    it "f.association :manager_id falls back to a select (no reflection on a plain ActiveModel object)" do
      expect(field("manager_id").name).to eq("select")
    end

    it "f.input :color, as: :color renders radio inputs" do
      html = Nokogiri::HTML5.fragment(response.body)
      swatches = html.css('input[name="person[color]"]')
      expect(swatches.map { |s| s["type"] }.uniq).to eq(["radio"])
    end

    it "f.input :avatar_rating, as: :rating renders the rating component" do
      html = Nokogiri::HTML5.fragment(response.body)
      expect(html.css('[data-controller*="rating"], .star-rating, [name="person[avatar_rating]"]')).not_to be_empty
    end

    it "f.input :theme, as: :imagecheck renders imagecheck radio inputs" do
      html = Nokogiri::HTML5.fragment(response.body)
      expect(html.css("input.form-imagecheck-input").map { |i| i["type"] }.uniq).to eq(["radio"])
    end

    it "f.input :resume, as: :file renders a file input" do
      expect(field("resume")["type"]).to eq("file")
    end

    it "f.input_field :search_query renders a naked input with no wrapping label" do
      input = field("search_query")
      expect(input["type"]).to eq("text")
      expect(input["placeholder"]).to eq("Naked input, no label/wrapper")
    end

    it "f.input :appointment_at (inferred :datetime) renders a native datetime-local input" do
      expect(field("appointment_at")["type"]).to eq("datetime-local")
    end

    it "f.input :salary (inferred :decimal) renders a number input with step=any" do
      html = Nokogiri::HTML5.fragment(response.body)
      salary_inputs = html.css('input[name="person[salary]"]')
      expect(salary_inputs.map { |i| i["type"] }.uniq).to eq(["number"])
      expect(salary_inputs.map { |i| i["step"] }.uniq).to eq(["any"])
    end

    it "f.input as: :input_group wraps prepend/append text around the field" do
      html = Nokogiri::HTML5.fragment(response.body)
      groups = html.css("div.input-group")
      expect(groups.map { |g| g.css(".input-group-text").map(&:text) }).to include(["$"], [".com"])
    end

    it "renders every registered form_builder demo's slug as a card id (single-sourced against the registry)" do
      html = Nokogiri::HTML5.fragment(response.body)
      TablerUi::Docs::DemoRegistry.for(:form_builder).each do |demo|
        expect(html.at_css("##{demo.slug}")).not_to be_nil, "no #{demo.slug} card rendered"
      end
    end

    it "does not show the error notification banner without ?with_errors=1" do
      html = Nokogiri::HTML5.fragment(response.body)
      expect(html.css(".alert-danger")).to be_empty
    end
  end

  describe "GET /ui/forms?with_errors=1" do
    before { get "/ui/forms", params: { with_errors: 1 } }

    it "renders 200" do
      expect(response).to have_http_status(:ok)
    end

    # FormBuilder#error_notification delegates to @template.tabler_ui.alert
    # (lib/tabler_ui/form_builder.rb) rather than hand-rolling the markup --
    # this proves that delegation still renders a real Tabler alert banner
    # listing the forced validation error.
    it "renders f.error_notification as a danger alert listing the forced :email error" do
      html = Nokogiri::HTML5.fragment(response.body)
      banner = html.at_css(".alert-danger")

      expect(banner).not_to be_nil
      expect(banner.text).to include("is already taken")
    end

    it "marks the email field invalid inline" do
      expect(field("email")["class"]).to include("is-invalid")
    end

    it "still renders every field-level demo (the error state doesn't blow up the rest of the page)" do
      html = Nokogiri::HTML5.fragment(response.body)
      TablerUi::Docs::DemoRegistry.for(:form_builder).each do |demo|
        expect(html.at_css("##{demo.slug}")).not_to be_nil, "no #{demo.slug} card rendered"
      end
    end
  end
end
