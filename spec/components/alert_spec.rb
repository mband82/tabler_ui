# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Alert", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:alert)

    expect(fragment.css("div.alert")).not_to be_empty
    expect(fragment.css(".alert").first["role"]).to eq("alert")
  end

  it_behaves_like "an element with an html hook", :alert, {},
    hook: :html, selector: ".alert"

  it_behaves_like "an element with an html hook", :alert, { title: "Error" },
    hook: :title_html, selector: ".alert-heading"

  it_behaves_like "an element with an html hook", :alert, {},
    hook: :icon_html, selector: ".alert-icon"

  it_behaves_like "an element with an html hook", :alert, { url: "/changelog" },
    hook: :link_html, selector: "a.alert-link"

  it_behaves_like "an element with an html hook", :alert, { dismissible: true },
    hook: :dismiss_html, selector: "a.btn-close"

  it "appends a caller class to the alert's own classes, not replacing them" do
    fragment = component_fragment(:alert, color: "danger", html: { class: "hook-extra-class" })
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).to include("alert", "alert-danger", "hook-extra-class")
  end

  it "defaults to alert-info when color: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-info")
  end

  it "produces alert-<color> for a given color" do
    fragment = component_fragment(:alert, color: "danger")

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-danger")
  end

  it "raises ArgumentError naming alert for an unknown color" do
    expect { component_fragment(:alert, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:alert, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /alert/)
  end

  it "no longer accepts variant: -- passing it has no effect (rename regression)" do
    fragment = component_fragment(:alert, variant: "danger", text: "Hi")
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).not_to include("alert-danger")
    expect(classes).to include("alert-info")
  end

  it "no longer accepts message: -- passing it renders nothing (rename regression)" do
    fragment = component_fragment(:alert, message: "Old message")

    expect(fragment.to_html).not_to include("Old message")
  end

  it "no longer accepts link: -- passing it renders no action link (rename regression)" do
    fragment = component_fragment(:alert, link: "/somewhere", link_text: "Go")

    expect(fragment.css(".alert-link")).to be_empty
  end

  it "renders text: in an alert-description div (Tabler's own class -- also what " \
     "alert-important's contrast override targets, tabler.css .alert-important .alert-description)" do
    fragment = component_fragment(:alert, text: "Saved!")

    expect(fragment.css(".alert-description").text).to eq("Saved!")
  end

  it "renders the body slot's rich content when text: is omitted" do
    fragment = component_fragment(:alert) do |slots|
      slots.body { "<strong>Bold</strong>".html_safe }
    end

    expect(fragment.css("strong").text).to eq("Bold")
  end

  it "renders no body content when neither text: nor the body slot are given" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert-description")).to be_empty
  end

  it "renders title: in an h4.alert-heading (Tabler's own class, tabler.css .alert-heading)" do
    fragment = component_fragment(:alert, title: "Error")

    expect(fragment.css("h4.alert-heading").text).to eq("Error")
  end

  it "renders no title element when title: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert-heading")).to be_empty
  end

  it "renders a default icon based on color" do
    fragment = component_fragment(:alert, color: "danger")

    expect(fragment.css(".icon-tabler-alert-circle")).not_to be_empty
  end

  it "renders a custom icon: instead of the color's default" do
    fragment = component_fragment(:alert, color: "danger", icon: "download")

    expect(fragment.css(".icon-tabler-download")).not_to be_empty
    expect(fragment.css(".icon-tabler-alert-circle")).to be_empty
  end

  it "renders no icon when icon: false" do
    fragment = component_fragment(:alert, icon: false)

    expect(fragment.css(".alert-icon")).to be_empty
    expect(fragment.css("svg")).to be_empty
  end

  describe "regression: icon spacing -- no extra wrapper div between the icon and the content" do
    # Tabler's own .alert is `display: flex; flex-direction: row; gap: 1rem`
    # (tabler.css) -- it is itself the flex container, and `gap` only spaces
    # its own direct children. An earlier version wrapped the icon and the
    # content block in an extra `<div class="d-flex">`, which became a single
    # flex child of .alert with nothing for its own (unset) gap to separate,
    # so the icon rendered flush against the text. Asserting the parent/child
    # relationship directly so a reintroduced wrapper fails this test.
    it "keeps the icon svg as a direct child of .alert" do
      fragment = component_fragment(:alert, color: "danger")

      expect(fragment.css(".alert > svg.alert-icon")).not_to be_empty,
        "expected .alert-icon to be a direct child of .alert, in:\n#{fragment.to_html}"
    end

    it "keeps the content block as a direct child of .alert, a sibling of the icon" do
      fragment = component_fragment(:alert, color: "danger", title: "Error", text: "Something went wrong.")

      expect(fragment.css(".alert > div")).not_to be_empty,
        "expected the content block to be a direct child of .alert, in:\n#{fragment.to_html}"
      expect(fragment.css(".alert > div > h4.alert-heading")).not_to be_empty
      expect(fragment.css(".alert > div > .alert-description")).not_to be_empty
    end

    it "no longer wraps the icon and content in a d-flex div" do
      fragment = component_fragment(:alert, color: "danger", title: "Error", text: "Something went wrong.")

      expect(fragment.css(".d-flex")).to be_empty
    end
  end

  it "renders a dismiss button and alert-dismissible class for dismissible: true" do
    fragment = component_fragment(:alert, dismissible: true)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-dismissible")
    expect(fragment.css("a.btn-close[data-bs-dismiss='alert']")).not_to be_empty
  end

  it "renders the dismiss link with a translated aria-label by default" do
    fragment = component_fragment(:alert, dismissible: true)
    dismiss = fragment.css("a.btn-close").first

    expect(dismiss["aria-label"]).to eq("Close")
  end

  it "renders no dismiss button when dismissible: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".btn-close")).to be_empty
  end

  it "adds alert-important for important: true" do
    fragment = component_fragment(:alert, important: true)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-important")
  end

  it "renders url: and link_text: as the action link" do
    fragment = component_fragment(:alert, url: "/changelog", link_text: "See what's new")
    link = fragment.css("a.alert-link").first

    expect(link).not_to be_nil
    expect(link["href"]).to eq("/changelog")
    expect(link.text).to eq("See what's new")
  end

  it "defaults link_text: to 'Learn more' when url: is given without link_text:" do
    fragment = component_fragment(:alert, url: "/changelog")

    expect(fragment.css("a.alert-link").text).to eq("Learn more")
  end

  it "renders no action link when url: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert-link")).to be_empty
  end

  it "adds alert-minor for minor: true" do
    fragment = component_fragment(:alert, minor: true)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-minor")
  end

  it "combines alert-minor with a color" do
    fragment = component_fragment(:alert, minor: true, color: "danger")
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).to include("alert-minor", "alert-danger")
  end

  it "combines alert-minor with dismissible:" do
    fragment = component_fragment(:alert, minor: true, dismissible: true)
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).to include("alert-minor", "alert-dismissible")
  end

  it "renders no alert-minor when minor: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).not_to include("alert-minor")
  end

  it "produces alert-muted for color: 'muted'" do
    fragment = component_fragment(:alert, color: "muted")

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-muted")
  end

  it "does not let muted leak into the shared color palette (badge still rejects it)" do
    expect { component_fragment(:badge, color: "muted") }
      .to raise_error(ArgumentError, /muted/)
  end

  it "defaults to alert-link when link_style: is omitted" do
    fragment = component_fragment(:alert, url: "/changelog")
    link = fragment.css("a").first

    expect(link["class"].split(/\s+/)).to include("alert-link")
  end

  it "renders alert-action for link_style: :action, not alert-link" do
    fragment = component_fragment(:alert, url: "/changelog", link_style: :action)
    link = fragment.css("a").first
    classes = link["class"].split(/\s+/)

    expect(classes).to include("alert-action")
    expect(classes).not_to include("alert-link")
  end

  it "raises ArgumentError naming alert for an invalid link_style:" do
    expect { component_fragment(:alert, url: "/changelog", link_style: :bogus) }
      .to raise_error(ArgumentError, /bogus/)
    expect { component_fragment(:alert, url: "/changelog", link_style: :bogus) }
      .to raise_error(ArgumentError, /alert/)
  end

  describe "regression: rule 5 hooks leave default output unchanged" do
    it "still renders the action link with class before href, no attributes added" do
      fragment = component_fragment(:alert, url: "/changelog", link_text: "See what's new")
      link = fragment.css("a.alert-link").first

      expect(link.attribute_nodes.map(&:name)).to eq(%w[class href])
      expect(link["href"]).to eq("/changelog")
    end

    it "still renders the dismiss link with the same attributes, still on an <a>" do
      fragment = component_fragment(:alert, dismissible: true)
      dismiss = fragment.css("a.btn-close").first

      expect(dismiss).not_to be_nil
      expect(dismiss["data-bs-dismiss"]).to eq("alert")
      expect(dismiss["aria-label"]).to eq("Close")
    end

    it "still puts data-controller on the root element only when dismissible, after class/role" do
      fragment = component_fragment(:alert, dismissible: true)
      root = fragment.css(".alert").first

      expect(root["data-controller"]).to eq("tabler-ui--alert")
      expect(root.attribute_nodes.map(&:name)).to eq(%w[class role data-controller])
    end

    it "still omits data-controller entirely when not dismissible" do
      fragment = component_fragment(:alert)

      expect(fragment.css(".alert").first.attribute_nodes.map(&:name)).to eq(%w[class role])
    end
  end

  describe "link_html:" do
    it "applies alongside link_style: :action, on the .alert-action element" do
      fragment = component_fragment(:alert, url: "/changelog", link_style: :action,
                                              link_html: { class: "hook-extra-class" })
      link = fragment.css("a.alert-action").first

      expect(link["class"].split(/\s+/)).to include("alert-action", "hook-extra-class")
    end

    it "is not applied when url: is absent -- there is no action link to reach" do
      fragment = component_fragment(:alert, link_html: { class: "hook-extra-class" })

      expect(fragment.to_html).not_to include("hook-extra-class")
    end
  end

  describe "dismiss_html:" do
    it "is not applied when dismissible: is absent -- there is no dismiss link to reach" do
      fragment = component_fragment(:alert, dismiss_html: { class: "hook-extra-class" })

      expect(fragment.to_html).not_to include("hook-extra-class")
    end

    it "merges onto the dismiss link without dropping data-bs-dismiss/aria-label" do
      fragment = component_fragment(:alert, dismissible: true, dismiss_html: { class: "hook-extra-class" })
      dismiss = fragment.css("a.btn-close").first

      expect(dismiss["class"].split(/\s+/)).to include("btn-close", "hook-extra-class")
      expect(dismiss["data-bs-dismiss"]).to eq("alert")
      expect(dismiss["aria-label"]).to eq("Close")
    end

    it "lets a caller override the default aria-label, same as any other non-class attribute" do
      fragment = component_fragment(:alert, dismissible: true, dismiss_html: { "aria-label": "Dismiss" })
      dismiss = fragment.css("a.btn-close").first

      expect(dismiss["aria-label"]).to eq("Dismiss")
    end
  end
end
