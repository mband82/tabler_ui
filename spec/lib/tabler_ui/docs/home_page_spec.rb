# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# The getting-started landing page (GET /ui, PagesController#home): install,
# both asset pipelines, JS load order, mounting, and one live demo -- see
# docs/app/views/tabler_ui/docs/pages/home.html.erb. It deliberately does NOT
# duplicate the component list; the sidebar (rendered on every docs page)
# already does that.
RSpec.describe "TablerUi::Docs getting-started page", type: :request do
  before { get "/ui" }

  it "renders 200" do
    expect(response).to have_http_status(:ok)
  end

  it "shows the install snippet" do
    expect(response.body).to include('gem "tabler_ui", git: "https://github.com/webbastelbude/tabler_ui.git"')
  end

  it "documents both asset pipelines" do
    expect(response.body).to include("*= require tabler_ui")
    expect(response.body).to include('stylesheet_link_tag "tabler_ui_all"')
  end

  it "documents the Stimulus-before-import load order" do
    expect(response.body).to include("window.Stimulus = application")
    expect(response.body).to include('import "tabler_ui"')
  end

  it "shows how to mount the docs engine" do
    expect(response.body).to include('mount TablerUi::Docs::Engine, at: "/ui"')
  end

  it "embeds the button-shape demo live, not just as a code sample" do
    demo = TablerUi::Docs::DemoRegistry.find("button-shape")
    fragment = Nokogiri::HTML5.fragment(response.body)

    expect(fragment.at_css("##{demo.slug}")).not_to be_nil
    button_texts = fragment.css(".docs-demo-example a, .docs-demo-example button").map { |el| el.text.strip }
    expect(button_texts).to include("Pill")
  end

  it "links to the component reference and the form builder, and mentions the component count and search" do
    fragment = Nokogiri::HTML5.fragment(response.body)
    hrefs = fragment.css("a").map { |a| a["href"] }

    count = TablerUi::Docs::Navigation.components.size

    expect(hrefs).to include("/ui/components/button")
    expect(hrefs).to include("/ui/forms")
    expect(response.body).to include("#{count} #{'component'.pluralize(count)}")
    expect(response.body).to include("Search")
  end
end
