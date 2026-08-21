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

  it_behaves_like "an element with an html hook", :rating, {},
    hook: :wrapper_html, selector: "span.tabler-ui-rating"

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

    it "sets the Stimulus color-value data attribute from color:" do
      fragment = component_fragment(:rating, color: "red")

      expect(fragment.css("span.tabler-ui-rating").first["data-tabler-ui--rating-color-value"]).to eq("red")
    end
  end

  it "no longer reads variant: -- it's ignored, not an error" do
    fragment = component_fragment(:rating, variant: "red")

    expect(fragment.css("span.tabler-ui-rating").first["data-tabler-ui--rating-color-value"]).to be_nil
  end

  # Regression: the Stimulus controller used to live on the <select> itself.
  # star-rating.js reparents whatever element it's given (see
  # app/assets/javascripts/star-rating.js#buildWidget/#destroy), so with the
  # controller on the <select>, Stimulus saw each reparent as the
  # controller's element being removed/re-added and disconnected/reconnected
  # it -- disconnect tore the widget down (another reparent), which
  # reconnected and rebuilt it (another reparent), forever: an infinite
  # connect/mutate/disconnect/mutate loop that hung the browser tab with no
  # console error. The controller now lives on a stable wrapper <span> that
  # star-rating.js never moves; the <select> is only a Stimulus target.
  it "puts the Stimulus controller on the wrapper span, not the select" do
    fragment = component_fragment(:rating)

    expect(fragment.css("select").first["data-controller"]).to be_nil
    expect(fragment.css("span.tabler-ui-rating").first["data-controller"]).to eq("tabler-ui--rating")
  end

  it "marks the select as the rating Stimulus target" do
    fragment = component_fragment(:rating)

    expect(fragment.css("select").first["data-tabler-ui--rating-target"]).to eq("select")
  end

  it "carries all the Stimulus data attributes rating_controller.js expects" do
    fragment = component_fragment(:rating, size: "sm", color: "green",
                                             tooltip: false, clearable: false)
    wrapper = fragment.css("span.tabler-ui-rating").first

    expect(wrapper["data-controller"]).to eq("tabler-ui--rating")
    expect(wrapper["data-tabler-ui--rating-tooltip-value"]).to eq("false")
    expect(wrapper["data-tabler-ui--rating-clearable-value"]).to eq("false")
    expect(wrapper["data-tabler-ui--rating-color-value"]).to eq("green")
    expect(wrapper["data-tabler-ui--rating-size-value"]).to eq("sm")
  end

  it "defaults tooltip and clearable to true" do
    fragment = component_fragment(:rating)
    wrapper = fragment.css("span.tabler-ui-rating").first

    expect(wrapper["data-tabler-ui--rating-tooltip-value"]).to eq("true")
    expect(wrapper["data-tabler-ui--rating-clearable-value"]).to eq("true")
  end

  it "defaults name to 'rating' and generates a deterministic id from it" do
    fragment = component_fragment(:rating)
    select = fragment.css("select").first

    expect(select["name"]).to eq("rating")
    expect(select["id"]).to eq("rating-rating")
  end

  it "renders a custom id: and name:" do
    fragment = component_fragment(:rating, id: "custom-id", name: "custom_name")
    select = fragment.css("select").first

    expect(select["id"]).to eq("custom-id")
    expect(select["name"]).to eq("custom_name")
  end

  # Regression: app/components/tabler_ui/rating/component.rb used to generate
  # a random id (SecureRandom.hex) when id: was omitted, so every render of
  # the same options produced different markup -- breaking fragment/HTTP
  # caching and any output-stability assertion. Fixed by deriving the id
  # deterministically from name: instead, mirroring table's filter_field_id.
  describe "deterministic id generation" do
    it "renders byte-identical HTML across two renders of the same options" do
      first = render_component(:rating, name: "satisfaction")
      second = render_component(:rating, name: "satisfaction")

      expect(first).to eq(second)
    end

    it "derives the generated id from name: -- different names get different ids" do
      fragment_a = component_fragment(:rating, name: "satisfaction")
      fragment_b = component_fragment(:rating, name: "quality")

      id_a = fragment_a.css("select").first["id"]
      id_b = fragment_b.css("select").first["id"]

      expect(id_a).to eq("rating-satisfaction")
      expect(id_b).to eq("rating-quality")
      expect(id_a).not_to eq(id_b)
    end

    it "an explicit id: still overrides the generated one" do
      fragment = component_fragment(:rating, name: "satisfaction", id: "explicit-id")

      expect(fragment.css("select").first["id"]).to eq("explicit-id")
    end
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
