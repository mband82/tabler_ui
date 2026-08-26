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

  it "align: :start does not produce dropdown-menu-end" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin", align: :start) { |dd| dd.item("Users", url: "/admin/users", active: false) }
      end
    end

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-end")
  end

  it "align: nil does not produce dropdown-menu-end" do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin", align: nil) { |dd| dd.item("Users", url: "/admin/users", active: false) }
      end
    end

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-end")
  end

  it 'align: "end" (string) produces dropdown-menu-end' do
    fragment = component_fragment(:navbar) do |navbar|
      navbar.left do |nav|
        nav.dropdown("Admin", align: "end") { |dd| dd.item("Users", url: "/admin/users", active: false) }
      end
    end

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-end")
  end

  it 'align: "right" raises ArgumentError -- the old vocabulary is no longer silently coerced' do
    expect {
      component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin", align: "right") { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end
    }.to raise_error(ArgumentError, /:start.*:end/)
  end

  it "align: :middle raises ArgumentError" do
    expect {
      component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin", align: :middle) { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end
    }.to raise_error(ArgumentError, /:start.*:end/)
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

  it "defaults to navbar-expand-lg on the root" do
    fragment = component_fragment(:navbar)

    classes = fragment.css("header.navbar").first["class"].split(/\s+/)
    expect(classes).to include("navbar", "navbar-expand-lg", "d-print-none")
  end

  TablerUi::Breakpoint::ALL.each do |breakpoint|
    it "expand: #{breakpoint.inspect} puts navbar-expand-#{breakpoint} on the root, and only that breakpoint class" do
      fragment = component_fragment(:navbar, expand: breakpoint)

      classes = fragment.css("header.navbar").first["class"].split(/\s+/)
      expand_classes = classes.grep(/\Anavbar-expand-/)

      expect(expand_classes).to eq(["navbar-expand-#{breakpoint}"])
    end
  end

  it "expand: with an invalid breakpoint raises ArgumentError" do
    expect {
      component_fragment(:navbar, expand: "huge")
    }.to raise_error(ArgumentError, /unknown breakpoint/)
  end

  it "dark: true adds navbar-dark to the root" do
    fragment = component_fragment(:navbar, dark: true)

    expect(fragment.css("header.navbar").first["class"].split(/\s+/)).to include("navbar-dark")
  end

  it "transparent: true adds navbar-transparent to the root" do
    fragment = component_fragment(:navbar, transparent: true)

    expect(fragment.css("header.navbar").first["class"].split(/\s+/)).to include("navbar-transparent")
  end

  it "overlap: true adds navbar-overlap to the root" do
    fragment = component_fragment(:navbar, overlap: true)

    expect(fragment.css("header.navbar").first["class"].split(/\s+/)).to include("navbar-overlap")
  end

  it "dark:, transparent: and overlap: together produce all three classes alongside the base ones" do
    fragment = component_fragment(:navbar, dark: true, transparent: true, overlap: true)

    classes = fragment.css("header.navbar").first["class"].split(/\s+/)
    expect(classes).to include("navbar", "navbar-expand-lg", "d-print-none",
                                "navbar-dark", "navbar-transparent", "navbar-overlap")
  end

  it "nav_scroll: true puts navbar-nav-scroll on the menu element, not the root" do
    fragment = component_fragment(:navbar, nav_scroll: true)

    expect(fragment.css(".navbar-collapse").first["class"].split(/\s+/)).to include("navbar-nav-scroll")
    expect(fragment.css("header.navbar").first["class"].split(/\s+/)).not_to include("navbar-nav-scroll")
  end

  it "menu_html: style: still lands on the menu element alongside nav_scroll:" do
    fragment = component_fragment(:navbar, nav_scroll: true, menu_html: { style: "--tblr-scroll-height: 300px" })

    menu = fragment.css(".navbar-collapse").first
    expect(menu["style"]).to eq("--tblr-scroll-height: 300px")
    expect(menu["class"].split(/\s+/)).to include("navbar-nav-scroll")
  end

  # Not routed through the shared "an element with an html hook" example --
  # that example only supports plain kwargs base_options, and a dropdown
  # toggle only exists once a builder block has added a #dropdown item.
  describe "dropdown_toggle_html: -- rule 5 hook contract" do
    def navbar_with_dropdown(dropdown_toggle_html: nil)
      component_fragment(:navbar, dropdown_toggle_html: dropdown_toggle_html) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end
    end

    it "keeps the component's own classes on the .dropdown-toggle element" do
      fragment = navbar_with_dropdown
      expect(fragment.css(".dropdown-toggle")).not_to be_empty
    end

    it "appends a caller-supplied class instead of replacing the component's own" do
      fragment = navbar_with_dropdown(dropdown_toggle_html: { class: "hook-extra-class" })
      classes = fragment.css(".dropdown-toggle").first["class"].split(/\s+/)

      expect(classes).to include("nav-link", "dropdown-toggle", "hook-extra-class")
    end

    it "passes through a caller-supplied id" do
      fragment = navbar_with_dropdown(dropdown_toggle_html: { id: "hook-test-id" })
      expect(fragment.css(".dropdown-toggle").first["id"]).to eq("hook-test-id")
    end

    it "passes through caller-supplied data attributes" do
      fragment = navbar_with_dropdown(dropdown_toggle_html: { data: { testid: "hook-test-data" } })
      expect(fragment.css(".dropdown-toggle").first["data-testid"]).to eq("hook-test-data")
    end
  end

  describe "link_html:" do
    it "applies component-level link_html: to a plain nav link's <a>, via a plain Hash" do
      fragment = component_fragment(:navbar, link_html: { class: "hook-extra-class", id: "hook-test-id" }) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false
        end
      end

      link = fragment.css("a.nav-link").first
      expect(link["class"].split(/\s+/)).to include("nav-link", "hook-extra-class")
      expect(link["id"]).to eq("hook-test-id")
    end

    it "applies component-level link_html: as a callable taking the item, varying per link" do
      fragment = component_fragment(
        :navbar, link_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
      ) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false
          nav.add "About", url: "/about", active: false
        end
      end

      links = fragment.css("a.nav-link")
      expect(links[0]["class"].split(/\s+/)).to include("callable-class-home")
      expect(links[0]["class"].split(/\s+/)).not_to include("callable-class-about")
      expect(links[1]["class"].split(/\s+/)).to include("callable-class-about")
    end

    it "applies a per-item link_html: (NavigationGroup#add) to that item's <a> only, via a plain Hash" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false, link_html: { class: "hook-extra-class", id: "hook-test-id" }
          nav.add "About", url: "/about", active: false
        end
      end

      links = fragment.css("a.nav-link")
      expect(links[0]["class"].split(/\s+/)).to include("hook-extra-class")
      expect(links[0]["id"]).to eq("hook-test-id")
      expect(links[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    end

    it "applies a per-item link_html: via a callable taking the item, varying per link" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false, link_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
          nav.add "About", url: "/about", active: false, link_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
        end
      end

      links = fragment.css("a.nav-link")
      expect(links[0]["class"].split(/\s+/)).to include("callable-class-home")
      expect(links[1]["class"].split(/\s+/)).to include("callable-class-about")
      expect(links[1]["class"].split(/\s+/)).not_to include("callable-class-home")
    end

    it "a per-item link_html: wins over the component-level link_html: when both are given" do
      fragment = component_fragment(:navbar, link_html: { class: "component-level" }) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false, link_html: { id: "item-level" }
        end
      end

      link = fragment.css("a.nav-link").first
      expect(link["class"].split(/\s+/)).to include("nav-link", "component-level")
      expect(link["id"]).to eq("item-level")
    end

    it "reaches the <button> inside button_to's <form>, not the <a>, for a non-GET nav link" do
      fragment = component_fragment(:navbar, link_html: { class: "hook-extra-class" }) do |navbar|
        navbar.left do |nav|
          nav.add "Logout", url: "/logout", method: :delete, active: false
        end
      end

      button = fragment.css("form.button_to input[type=submit]").first
      expect(button["class"].split(/\s+/)).to include("nav-link", "hook-extra-class")
      expect(fragment.css("a.hook-extra-class")).to be_empty
    end
  end

  describe "dropdown_toggle_html:" do
    it "a caller's data: on dropdown_toggle_html: coexists with the component's own " \
       "data-bs-toggle and data-controller, instead of replacing them" do
      fragment = component_fragment(
        :navbar, dropdown_toggle_html: { data: { testid: "admin-toggle" } }
      ) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end

      toggle = fragment.css(".dropdown-toggle").first
      expect(toggle["data-bs-toggle"]).to eq("dropdown")
      expect(toggle["data-controller"]).to eq("tabler-ui--dropdown-menu")
      expect(toggle["data-testid"]).to eq("admin-toggle")
    end

    it "applies dropdown_toggle_html: as a callable taking the item" do
      fragment = component_fragment(
        :navbar, dropdown_toggle_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }
      ) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end

      toggle = fragment.css(".dropdown-toggle").first
      expect(toggle["class"].split(/\s+/)).to include("callable-class-admin")
    end
  end

  describe "per-sub-item link_html: (DropDownProxy#item)" do
    it "applies to that sub-item's <a> only, via a plain Hash" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false, link_html: { class: "hook-extra-class", id: "hook-test-id" })
            dd.item("Settings", url: "/admin/settings", active: false)
          end
        end
      end

      items = fragment.css(".dropdown-item")
      expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
      expect(items[0]["id"]).to eq("hook-test-id")
      expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    end

    it "applies via a callable taking the item, varying per sub-item" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false, link_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
            dd.item("Settings", url: "/admin/settings", active: false, link_html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
          end
        end
      end

      items = fragment.css(".dropdown-item")
      expect(items[0]["class"].split(/\s+/)).to include("callable-class-users")
      expect(items[1]["class"].split(/\s+/)).to include("callable-class-settings")
      expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-users")
    end

    it "reaches the <button> inside button_to's <form>, not the <a>, for a non-GET sub-item" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Delete", url: "/admin/delete", method: :delete, active: false, link_html: { class: "hook-extra-class" })
          end
        end
      end

      button = fragment.css("form.button_to button").first
      expect(button["class"].split(/\s+/)).to include("dropdown-item", "hook-extra-class")
    end
  end

  describe "per-sub-item html: (DropDownProxy#item) -- rule 5 root hook" do
    it "applies to that sub-item's <a> only, via a plain Hash" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false, html: { class: "hook-extra-class", id: "hook-test-id" })
            dd.item("Settings", url: "/admin/settings", active: false)
          end
        end
      end

      items = fragment.css(".dropdown-item")
      expect(items[0]["class"].split(/\s+/)).to include("dropdown-item", "hook-extra-class")
      expect(items[0]["id"]).to eq("hook-test-id")
      expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
      expect(items[1]["id"]).to be_nil
    end

    it "applies via a callable taking the item, varying per sub-item" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false,
                             html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
            dd.item("Settings", url: "/admin/settings", active: false,
                                 html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
          end
        end
      end

      items = fragment.css(".dropdown-item")
      expect(items[0]["class"].split(/\s+/)).to include("callable-class-users")
      expect(items[1]["class"].split(/\s+/)).to include("callable-class-settings")
      expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-users")
    end

    it "passes through caller-supplied data/aria attributes" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false,
                             html: { data: { testid: "hook-test-data" }, aria: { label: "hook-test-aria" } })
          end
        end
      end

      item = fragment.css(".dropdown-item").first
      expect(item["data-testid"]).to eq("hook-test-data")
      expect(item["aria-label"]).to eq("hook-test-aria")
    end

    it "reaches the <button> inside button_to's <form>, not the <a>, for a non-GET sub-item" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Delete", url: "/admin/delete", method: :delete, active: false, html: { class: "hook-extra-class" })
          end
        end
      end

      button = fragment.css("form.button_to button").first
      expect(button["class"].split(/\s+/)).to include("dropdown-item", "hook-extra-class")
    end

    it "a per-item link_html: wins over the item's own html: when both set the same attribute" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false,
                             html: { id: "html-id" }, link_html: { id: "link-html-id" })
          end
        end
      end

      expect(fragment.css(".dropdown-item").first["id"]).to eq("link-html-id")
    end

    it "html: and link_html: classes both survive alongside the component's own dropdown-item class" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false,
                             html: { class: "html-class" }, link_html: { class: "link-html-class" })
          end
        end
      end

      classes = fragment.css(".dropdown-item").first["class"].split(/\s+/)
      expect(classes).to include("dropdown-item", "html-class", "link-html-class")
    end

    it "link_html: still targets the link unchanged when html: is absent" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false, link_html: { class: "hook-extra-class" })
          end
        end
      end

      classes = fragment.css(".dropdown-item").first["class"].split(/\s+/)
      expect(classes).to include("dropdown-item", "hook-extra-class")
    end
  end

  describe "DropDownProxy#divider html: -- rule 5 root hook" do
    it "applies to the divider's div.dropdown-divider, appending a caller class" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false)
            dd.divider(html: { class: "hook-extra-class", id: "hook-test-id" })
            dd.item("Settings", url: "/admin/settings", active: false)
          end
        end
      end

      divider = fragment.css(".dropdown-divider").first
      expect(divider["class"].split(/\s+/)).to include("dropdown-divider", "hook-extra-class")
      expect(divider["id"]).to eq("hook-test-id")
    end

    it "passes through caller-supplied data attributes" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false)
            dd.divider(html: { data: { testid: "hook-test-data" } })
            dd.item("Settings", url: "/admin/settings", active: false)
          end
        end
      end

      expect(fragment.css(".dropdown-divider").first["data-testid"]).to eq("hook-test-data")
    end
  end

  describe "DropDownProxy#header html: -- rule 5 root hook" do
    it "applies to the header's h6.dropdown-header, appending a caller class" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.header("Manage", html: { class: "hook-extra-class", id: "hook-test-id" })
            dd.item("Users", url: "/admin/users", active: false)
          end
        end
      end

      header = fragment.css(".dropdown-header").first
      expect(header["class"].split(/\s+/)).to include("dropdown-header", "hook-extra-class")
      expect(header["id"]).to eq("hook-test-id")
      expect(header.text.strip).to eq("Manage")
    end

    it "passes through caller-supplied data attributes" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") do |dd|
            dd.header("Manage", html: { data: { testid: "hook-test-data" } })
            dd.item("Users", url: "/admin/users", active: false)
          end
        end
      end

      expect(fragment.css(".dropdown-header").first["data-testid"]).to eq("hook-test-data")
    end
  end

  describe "REGRESSION: markup with no new rule 5 hook options is unchanged from before link_html:/" \
           "dropdown_toggle_html: were added" do
    it "a plain nav link's <a> is byte-identical" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/dashboard", target: "_blank", active: false
        end
      end

      expect(fragment.css(".nav-link").first.to_html).to eq('<a class="nav-link" target="_blank" href="/dashboard">Home</a>')
    end

    it "a non-GET nav link's button_to form is byte-identical" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Logout", url: "/logout", method: :delete, active: false
        end
      end

      expect(fragment.css("form.button_to").first.to_html).to eq(
        '<form class="button_to" method="post" action="/logout">' \
        '<input type="hidden" name="_method" value="delete" autocomplete="off">' \
        '<input class="nav-link" type="submit" value="Logout"></form>'
      )
    end

    it "a dropdown sub-item link and its non-GET counterpart are byte-identical" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin", align: :end) do |dd|
            dd.item("Settings", url: "/admin/settings", active: false, disabled: true)
            dd.item("Delete", url: "/admin/delete", method: :delete, active: false, target: "_blank")
          end
        end
      end

      items = fragment.css(".dropdown-item")
      expect(items[0].to_html).to eq(
        "<a class=\"dropdown-item disabled\" disabled=\"disabled\" href=\"/admin/settings\">\n                Settings\n</a>"
      )
      expect(items[1].to_html).to eq(
        "<button class=\"dropdown-item\" target=\"_blank\" type=\"submit\">\n                Delete\n</button>"
      )
    end

    it "the dropdown toggle carries exactly its original six attributes, with correct values " \
       "-- attribute *order* shifted (data: now built into the defaults hash so a caller's " \
       "own data: can deep-merge with it, see dropdown_toggle_attributes), but nothing is " \
       "missing, renamed, or added" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.dropdown("Admin") { |dd| dd.item("Users", url: "/admin/users", active: false) }
        end
      end

      toggle = fragment.css(".dropdown-toggle").first
      attrs = toggle.attributes.transform_values(&:value)
      expect(attrs).to eq(
        "class" => "nav-link dropdown-toggle",
        "href" => "#",
        "data-bs-toggle" => "dropdown",
        "data-controller" => "tabler-ui--dropdown-menu",
        "role" => "button",
        "aria-expanded" => "false"
      )
      expect(toggle.text.strip).to eq("Admin")
    end
  end

  # CLAUDE.md rule 8: auth: gating on navbar's own subitems -- group items
  # (NavigationGroup#add), dropdown items themselves (NavigationGroup#dropdown),
  # and the nested items inside a dropdown's block (DropDownProxy#item /
  # #divider / #header). TablerUi.auth_method is global, process-wide mutable
  # state -- restore it after every example so a custom auth_method here
  # never leaks into specs that run afterward (see dropdown_spec.rb / steps_spec.rb's
  # identical around block for the same reasoning).
  describe "auth: gating (CLAUDE.md rule 8)" do
    around do |example|
      original = TablerUi.auth_method
      example.run
      TablerUi.auth_method = original
    end

    it "REGRESSION: renders exactly as before under the default auth_method with no auth: anywhere" do
      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Home", url: "/", active: false
          nav.dropdown("Admin") do |dd|
            dd.item("Users", url: "/admin/users", active: false)
          end
        end
      end

      expect(fragment.css(".nav-link").map(&:text).map(&:strip)).to include("Home")
      expect(fragment.css(".dropdown-item").map(&:text).map(&:strip)).to include("Users")
    end

    it "omits a group item whose own auth: is denied" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:navbar) do |navbar|
        navbar.left do |nav|
          nav.add "Allowed", url: "/allowed", auth: :allowed, active: false
          nav.add "Denied", url: "/denied", auth: :denied, active: false
        end
      end

      titles = fragment.css(".nav-link").map(&:text).map(&:strip)
      expect(titles).to include("Allowed")
      expect(titles).not_to include("Denied")
    end

    # These examples build the component directly rather than going through
    # the dispatcher (component_fragment/tabler_ui.navbar): the dispatcher's
    # own top-level auth: gate (see ui_spec.rb's "auth: gating" describe
    # block) would deny the *entire* navbar call -- block never run -- whenever
    # the navbar-level auth: is itself denied, which would make it impossible
    # to exercise the inheritance/override branch in that case. Setting
    # .auth= directly is exactly what the dispatcher does internally right
    # after construction (see ui.rb's build path), so this exercises the same
    # inheritance logic without that confound.
    it "a group item with no auth: of its own inherits the navbar's own auth: -- denied" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :denied

      navbar.left { |nav| nav.add "Inherited", url: "/x" }

      expect(navbar.items_left).to be_empty
    end

    it "a group item with no auth: of its own inherits the navbar's own auth: -- allowed" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left { |nav| nav.add "Inherited", url: "/x" }

      expect(navbar.items_left.map(&:title)).to include("Inherited")
    end

    it "a group item's own auth: overrides an otherwise-denying navbar auth:" do
      TablerUi.auth_method = ->(value) { value == :allowed }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :denied

      navbar.left { |nav| nav.add "Overridden", url: "/x", auth: :allowed }

      expect(navbar.items_left.map(&:title)).to include("Overridden")
    end

    it "a group item's own auth: overrides an otherwise-allowing navbar auth:" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left { |nav| nav.add "Overridden", url: "/x", auth: :denied }

      expect(navbar.items_left).to be_empty
    end

    it "a dropdown item itself follows the same auth: rules as a plain item -- denied" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left { |nav| nav.dropdown("Admin", auth: :denied) { |dd| dd.item("Users", url: "/x") } }

      expect(navbar.items_left).to be_empty
    end

    it "a dropdown item itself follows the same auth: rules as a plain item -- allowed" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left { |nav| nav.dropdown("Admin", auth: :allowed) { |dd| dd.item("Users", url: "/x") } }

      expect(navbar.items_left.map(&:title)).to include("Admin")
    end

    it "a dropdown item with no auth: of its own inherits the group's own auth:" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :denied

      navbar.left { |nav| nav.dropdown("Admin") { |dd| dd.item("Users", url: "/x") } }

      expect(navbar.items_left).to be_empty
    end

    it "the two-level chain: a nested item with no auth: of its own inherits the DROPDOWN's " \
       "effective auth:, not the navbar's -- even when they'd resolve differently" do
      TablerUi.auth_method = ->(value) { value == :dropdown_level }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :navbar_level # would deny a nested item that inherited this directly

      navbar.left do |nav|
        nav.dropdown("Admin", auth: :dropdown_level) do |dd|
          dd.item("Users", url: "/admin/users")
        end
      end

      dropdown_item = navbar.items_left.first
      expect(dropdown_item.submenu.map(&:title)).to include("Users")
    end

    it "the two-level chain: a nested item with no auth: of its own is denied when the " \
       "dropdown's effective auth: is denied, even though the navbar's own auth: is allowed" do
      TablerUi.auth_method = ->(value) { value == :navbar_level }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :navbar_level

      navbar.left do |nav|
        nav.dropdown("Admin", auth: :dropdown_level) do |dd|
          dd.item("Users", url: "/admin/users")
        end
      end

      expect(navbar.items_left).to be_empty
    end

    it "a nested item's own explicit auth: overrides the dropdown's effective auth:" do
      TablerUi.auth_method = ->(value) { value == :allowed }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left do |nav|
        nav.dropdown("Admin", auth: :allowed) do |dd|
          dd.item("Denied", url: "/x", auth: :denied)
          dd.item("Kept", url: "/y")
        end
      end

      dropdown_item = navbar.items_left.first
      titles = dropdown_item.submenu.map(&:title)
      expect(titles).to include("Kept")
      expect(titles).not_to include("Denied")
    end

    it "a dropdown's divider and header also inherit and can be overridden the same way" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left do |nav|
        nav.dropdown("Admin") do |dd|
          dd.header("Kept header")
          dd.header("Denied header", auth: :denied)
          dd.divider
          dd.divider(auth: :denied)
        end
      end

      dropdown_item = navbar.items_left.first
      expect(dropdown_item.submenu.count { |sub| sub.type == :header }).to eq(1)
      expect(dropdown_item.submenu.find { |sub| sub.type == :header }&.title).to eq("Kept header")
      expect(dropdown_item.submenu.count { |sub| sub.type == :divider }).to eq(1)
    end

    it "dark_mode_toggle and divider group items are gated the same way -- denied" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left do |nav|
        nav.dark_mode_toggle(auth: :denied)
        nav.divider(auth: :denied)
      end

      expect(navbar.items_left).to be_empty
    end

    it "dark_mode_toggle and divider group items are gated the same way -- allowed" do
      TablerUi.auth_method = ->(value) { value != :denied }
      navbar = TablerUi::Navbar::Component.new
      navbar.auth = :allowed

      navbar.left do |nav|
        nav.dark_mode_toggle
        nav.divider
      end

      expect(navbar.items_left.map(&:type)).to eq([:dark_mode_toggle, :divider])
    end

    describe "the existing action:/subject:/can? mechanism -- unrelated to auth:, unaffected by it" do
      it "still hides an item can? denies, regardless of auth:" do
        view = tabler_ui_view_context
        view.define_singleton_method(:can?) { |_action, _subject| false }

        fragment = component_fragment(:navbar) do |navbar|
          navbar.left do |nav|
            nav.add "Admin", url: "/admin", action: :manage, subject: :users, active: false
          end
        end

        expect(fragment.css(".nav-link")).to be_empty
      end

      it "still shows an item can? allows, regardless of auth:" do
        view = tabler_ui_view_context
        view.define_singleton_method(:can?) { |_action, _subject| true }

        fragment = component_fragment(:navbar) do |navbar|
          navbar.left do |nav|
            nav.add "Admin", url: "/admin", action: :manage, subject: :users, active: false
          end
        end

        expect(fragment.css(".nav-link").map(&:text).map(&:strip)).to include("Admin")
      end

      it "auth: and can? gate the same item independently -- auth: allows it but can? still denies it" do
        TablerUi.auth_method = ->(value) { value != :denied }
        view = tabler_ui_view_context
        view.define_singleton_method(:can?) { |_action, _subject| false }

        fragment = component_fragment(:navbar) do |navbar|
          navbar.left do |nav|
            nav.add "Admin", url: "/admin", auth: :allowed, action: :manage, subject: :users, active: false
          end
        end

        expect(fragment.css(".nav-link")).to be_empty
      end
    end
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
