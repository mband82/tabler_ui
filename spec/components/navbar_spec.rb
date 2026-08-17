# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Navbar", type: :component do
  it "renders with no arguments" do
    fragment = component_fragment(:navbar)

    expect(fragment.css("header.navbar")).not_to be_empty
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Navbar::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:navbar) do |navbar|
      yielded = navbar
    end

    expect(yielded).to be_a(TablerUi::Navbar::Component)
    expect(yielded).to respond_to(:left)
    expect(yielded).to respond_to(:right)
  end

  it "renders items added to the left and right groups" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.add "Home", url: "/", active: false
      end
      navbar.right do |nav|
        nav.add "Logout", url: "/logout", active: false
      end
    end

    left_ul, right_ul = fragment.css("ul.navbar-nav")

    expect(left_ul.css(".nav-link").map(&:text)).to eq(["Home"])
    expect(right_ul.css(".nav-link").map(&:text)).to eq(["Logout"])
  end

  it "add with url: in options renders a link" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.add "Home", url: "/dashboard", active: false
      end
    end

    link = fragment.css(".nav-link").first
    expect(link.text.strip).to eq("Home")
    expect(link["href"]).to eq("/dashboard")
  end

  it "raises a helpful error when add is called the old keyword way" do
    expect {
      component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add(title: "Home")
        end
      end
    }.to raise_error(ArgumentError, /#add takes title positionally/)
  end

  it "renders a nested dropdown via .item / .divider / .header" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin") do |dd|
          dd.header("Manage")
          dd.item("Users", url: "/admin/users", active: false)
          dd.divider
          dd.item("Settings", url: "/admin/settings", active: false)
        end
      end
    end

    expect(fragment.css(".dropdown-toggle").first.text.strip).to eq("Admin")
    expect(fragment.css(".dropdown-header").first.text.strip).to eq("Manage")
    expect(fragment.css(".dropdown-divider")).not_to be_empty
    expect(fragment.css(".dropdown-item").map(&:text).map(&:strip)).to include("Users", "Settings")
  end

  it "no longer exposes .add / .add_divider on the dropdown proxy -- API reconciliation" do
    proxy = nil
    component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin") { |dd| proxy = dd }
      end
    end

    expect(proxy).not_to respond_to(:add)
    expect(proxy).not_to respond_to(:add_divider)
    expect(proxy).to respond_to(:item)
    expect(proxy).to respond_to(:divider)
    expect(proxy).to respond_to(:header)
  end

  it "align: :end produces dropdown-menu-end" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin", align: :end) { |dd| dd.item("Users", url: "/admin/users", active: false) }
      end
    end

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-end")
  end

  it "align: \"right\" no longer produces dropdown-menu-end -- regression" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin", align: "right") { |dd| dd.item("Users", url: "/admin/users", active: false) }
      end
    end

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-end")
  end

  it_behaves_like "an element with an html hook", :navbar, {},
    hook: :html, selector: "header.navbar"

  it_behaves_like "an element with an html hook", :navbar, {},
    hook: :brand_html, selector: ".navbar-brand"

  it_behaves_like "an element with an html hook", :navbar, {},
    hook: :toggler_html, selector: ".navbar-toggler"

  it_behaves_like "an element with an html hook", :navbar, {},
    hook: :menu_html, selector: ".navbar-collapse"

  it "applies per nav-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.add "Home", url: "/", active: false, html: { class: "hook-extra-class", id: "hook-test-id" }
        nav.add "About", url: "/about", active: false
      end
    end

    items = fragment.css("li.nav-item")

    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(items[1]["id"]).to be_nil
  end

  it "applies per nav-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.add "Home", url: "/", active: false, html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
        nav.add "About", url: "/about", active: false, html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
      end
    end

    items = fragment.css("li.nav-item")

    expect(items[0]["class"].split(/\s+/)).to include("callable-class-home")
    expect(items[0]["class"].split(/\s+/)).not_to include("callable-class-about")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-about")
  end

  it "brand: renders the given markup inside .navbar-brand" do
    fragment = component_fragment(:navbar, brand: "MyApp")

    expect(fragment.css(".navbar-brand").first.text.strip).to eq("MyApp")
  end

  it "brand_autodark: true (the default) adds navbar-brand-autodark" do
    fragment = component_fragment(:navbar, brand: "MyApp")

    expect(fragment.css(".navbar-brand").first["class"].split(/\s+/)).to include("navbar-brand-autodark")
  end

  it "brand_autodark: false omits navbar-brand-autodark" do
    fragment = component_fragment(:navbar, brand: "MyApp", brand_autodark: false)

    expect(fragment.css(".navbar-brand").first["class"].split(/\s+/)).not_to include("navbar-brand-autodark")
  end

  it "supports assigning navbar.brand = ... from inside the block, as before" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.brand = "MyApp"
    end

    expect(fragment.css(".navbar-brand").first.text.strip).to eq("MyApp")
  end

  it "marks the current page active automatically" do
    view = tabler_ui_view_context
    view.define_singleton_method(:request) { ActionDispatch::TestRequest.create("PATH_INFO" => "/dashboard") }

    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.add "Dashboard", url: "/dashboard"
        nav.add "Other", url: "/other"
      end
    end

    links = fragment.css(".nav-link")

    expect(links[0]["class"].split(/\s+/)).to include("active")
    expect(links[1]["class"].split(/\s+/)).not_to include("active")
    expect(fragment.css("li.nav-item")[0]["class"].split(/\s+/)).to include("active")
  end
end
