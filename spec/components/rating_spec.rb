# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Rating", type: :component do
  # Regression case: app/components/tabler_ui/rating/component.rb used to
  # assign `@options = options || default_options` before `@max_stars` was
  # set, so #default_options (which reads max_stars) blew up on
  # `max_stars - 1` with a NoMethodError -- tabler_ui.rating could not render
  # at all with its own declared defaults. Fixed by computing the default
  # choices lazily off the final @max_stars instead of eagerly in initialize.
  it "renders with no arguments at all, without raising" do
    fragment = component_fragment(:rating)

    expect(fragment.css("select")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders with an explicit choices: list" do
    fragment = component_fragment(:rating,
                                   choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Good" }])
    options = fragment.css("option")

    expect(options.map(&:text)).to eq(%w[Bad Good])
    expect(options.map { |o| o["value"] }).to eq(%w[1 2])
  end

  it_behaves_like "an element with an html hook", :rating, {},
    hook: :html, selector: "select.form-select"

  it "appends a caller class to the select's own class, not replacing it" do
    fragment = component_fragment(:rating, html: { class: "hook-extra-class" })
    classes = fragment.css("select").first["class"].split(/\s+/)

    expect(classes).to include("form-select", "hook-extra-class")
  end

  describe "max_stars:" do
    it "produces 2 choices (blank + Excellent) for max_stars: 1" do
      fragment = component_fragment(:rating, max_stars: 1)

      expect(fragment.css("option").size).to eq(2)
    end

    it "produces 3 choices for max_stars: 2" do
      fragment = component_fragment(:rating, max_stars: 2)

      expect(fragment.css("option").size).to eq(3)
    end

    it "produces 6 choices for the default max_stars: 5" do
      fragment = component_fragment(:rating)

      expect(fragment.css("option").size).to eq(6)
    end
  end

  describe "color:" do
    it "accepts a valid color" do
      expect { component_fragment(:rating, color: "azure") }.not_to raise_error
    end

    it "raises ArgumentError for an unknown color" do
      expect { component_fragment(:rating, color: "not-a-color") }.to raise_error(ArgumentError, /not-a-color/)
    end

    it "sets the Stimulus variant-value data attribute from color:" do
      fragment = component_fragment(:rating, color: "red")

      expect(fragment.css("select").first["data-tabler-ui--rating-variant-value"]).to eq("red")
    end
  end

  it "no longer reads variant: -- it's ignored, not an error" do
    fragment = component_fragment(:rating, variant: "red")

    expect(fragment.css("select").first["data-tabler-ui--rating-variant-value"]).to be_nil
  end

  it "carries all the Stimulus data attributes rating_controller.js expects" do
    fragment = component_fragment(:rating, id: "my-rating", size: "sm", color: "green",
                                             tooltip: false, clearable: false)
    select = fragment.css("select").first

    expect(select["data-controller"]).to eq("tabler-ui--rating")
    expect(select["data-tabler-ui--rating-id-value"]).to eq("my-rating")
    expect(select["data-tabler-ui--rating-tooltip-value"]).to eq("false")
    expect(select["data-tabler-ui--rating-clearable-value"]).to eq("false")
    expect(select["data-tabler-ui--rating-variant-value"]).to eq("green")
    expect(select["data-tabler-ui--rating-size-value"]).to eq("sm")
  end

  it "defaults tooltip and clearable to true" do
    fragment = component_fragment(:rating)
    select = fragment.css("select").first

    expect(select["data-tabler-ui--rating-tooltip-value"]).to eq("true")
    expect(select["data-tabler-ui--rating-clearable-value"]).to eq("true")
  end

  it "defaults name to 'rating' and generates an id" do
    fragment = component_fragment(:rating)
    select = fragment.css("select").first

    expect(select["name"]).to eq("rating")
    expect(select["id"]).to match(/\Arating-[0-9a-f]+\z/)
  end

  it "renders a custom id: and name:" do
    fragment = component_fragment(:rating, id: "custom-id", name: "custom_name")
    select = fragment.css("select").first

    expect(select["id"]).to eq("custom-id")
    expect(select["name"]).to eq("custom_name")
  end

  it "marks the value: option selected" do
    fragment = component_fragment(:rating, value: 3)
    selected = fragment.css("option[selected]").first

    expect(selected["value"]).to eq("3")
  end

  it "renders required: and disabled: as before" do
    fragment = component_fragment(:rating, required: true, disabled: true)
    select = fragment.css("select").first

    expect(select["required"]).to eq("required")
    expect(select["disabled"]).to eq("disabled")
  end

  it "defaults required: and disabled: to false" do
    fragment = component_fragment(:rating)
    select = fragment.css("select").first

    expect(select["required"]).to be_nil
    expect(select["disabled"]).to be_nil
  end
end
