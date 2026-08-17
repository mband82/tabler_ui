# frozen_string_literal: true

# Code snippets shown alongside each rendered example. Deliberately kept in a
# plain .rb file, not .erb: ERB's tag scanner is a naive text scan for
# <%/%>, with no awareness of Ruby's own heredoc/string nesting -- a snippet
# heredoc containing literal <%= ... %> text, embedded inside an .erb file's
# own <% %> tag, corrupts the compiled template (confirmed empirically while
# building this showcase; see the build report). Here, in a plain .rb file,
# <% and %> are just ordinary characters.
module ShowcaseHelper
  SNIPPETS = {
    layout_1: <<~'ERBSRC',
      <%= tabler_ui.navbar(brand: link_to("MyApp", "#")) do |navbar| %>
        <% navbar.left do |nav| %>
          <% nav.add "Home", url: "#", active: true %>
          <% nav.add "Reports", url: "#" %>
          <% nav.dropdown "Admin", align: :end do |dd| %>
            <% dd.header "Manage" %>
            <% dd.item "Users", url: "#", icon: "users" %>
            <% dd.divider %>
            <% dd.item "Settings", url: "#", icon: "settings" %>
          <% end %>
        <% end %>
        <% navbar.right do |nav| %>
          <% nav.dark_mode_toggle %>
        <% end %>
      <% end %>
    ERBSRC
    layout_2: <<~'ERBSRC',
      <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" do |slots| %>
        <% slots.buttons do %>
          <%= tabler_ui.button text: "New report", color: "primary", icon: "plus" %>
        <% end %>
      <% end %>
    ERBSRC
    layout_3: <<~'ERBSRC',
      <%= tabler_ui.card title: "Card title" do |slots| %>
        <% slots.body { "Card body content." } %>
        <% slots.footer { "Updated 3 min ago" } %>
      <% end %>
    ERBSRC
    layout_4: <<~'ERBSRC',
      <%= tabler_ui.card title: "Server status", status: "danger", stacked: true do |slots| %>
        <% slots.body { "3 servers are unreachable." } %>
      <% end %>
    ERBSRC
    layout_5: <<~'ERBSRC',
      columns = [
        { label: "Name", value: ->(row) { row[:name] } },
        { label: "Role", value: ->(row) { row[:role] } },
        { label: "Status", class: "text-end", value: ->(row) { tabler_ui.status(text: row[:status], dot: true) } }
      ]
      <%= tabler_ui.table columns: columns, data: rows, striped: true, hover: true,
                           row_html: ->(row) { { class: "table-warning" } if row[:status] == "Away" } %>
    ERBSRC
    layout_6: <<~'ERBSRC',
      <%= tabler_ui.datagrid do |dg| %>
        <% dg.item "Full name", content: "Ada Lovelace" %>
        <% dg.item "Email", content: "ada@example.com" %>
        <% dg.item "Bio" do %>
          <strong>Mathematician</strong> and writer.
        <% end %>
      <% end %>
    ERBSRC
    layout_7: <<~'ERBSRC',
      <%= tabler_ui.tabs("demo-tabs", style: :pills) do |tabs| %>
        <% tabs.tab("Inbox", icon: "mail", badge: "3") do %>
          You have 3 unread messages.
        <% end %>
        <% tabs.tab("Sent", icon: "send") do %>
          Nothing new here.
        <% end %>
        <% tabs.tab("Archive", badge: { text: "12", color: "red" }) do %>
          12 archived threads.
        <% end %>
      <% end %>
    ERBSRC
    layout_8: <<~'ERBSRC',
      <%= tabler_ui.settings_page("demo-settings", title: "Settings") do |sp| %>
        <% sp.item("General", icon: "settings") do %>
          General settings content.
        <% end %>
        <% sp.item("Security", icon: "shield-check") do %>
          Security settings content.
        <% end %>
        <% sp.item("Notifications", icon: "bell") do %>
          Notification settings content.
        <% end %>
      <% end %>
    ERBSRC
    layout_9: <<~'ERBSRC',
      <%= tabler_ui.accordion("demo-accordion", flush: true, toggle_style: :plus) do |acc| %>
        <% acc.item("What is Tabler UI?", open: true, icon: "info-circle") do %>
          A Rails component library on top of the Tabler.io design system.
        <% end %>
        <% acc.item("Is it free?") do %>
          Yes, MIT licensed.
        <% end %>
        <% acc.item("Does it need a database?") do %>
          No -- every component is a stateless view helper.
        <% end %>
      <% end %>
    ERBSRC

    content_1: <<~'ERBSRC',
      <%= tabler_ui.badge text: "New", color: "blue" %>
      <%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
      <%= tabler_ui.badge text: "4", color: "red", pill: true %>
      <%= tabler_ui.badge text: "Draft", color: "secondary", outline: true %>
      <%= tabler_ui.badge text: "Star", color: "yellow", icon: "star" %>
      <%= tabler_ui.badge color: "red", notification: true, blink: true %>
    ERBSRC
    content_2: <<~'ERBSRC',
      <%= tabler_ui.alert color: "success", text: "Your changes have been saved!" %>
      <%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
      <%= tabler_ui.alert color: "warning", text: "Your trial expires in 3 days.", important: true %>
      <%= tabler_ui.alert color: "info", text: "New update available.", url: "#", link_text: "See what's new" %>
    ERBSRC
    content_3: <<~'ERBSRC',
      <%= tabler_ui.avatar initials: "JD", size: "md" %>
      <%= tabler_ui.avatar image: "https://picsum.photos/200", size: "md" %>
      <%= tabler_ui.avatar name: "Ada Lovelace", size: "md" %>
      <%= tabler_ui.avatar initials: "SM", size: "xl" %>
      <%= tabler_ui.avatar initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin" %>
    ERBSRC
    content_4: <<~'ERBSRC',
      <%= tabler_ui.icon icon: "heart" %>
      <%= tabler_ui.icon icon: "heart", filled: true, color: "danger" %>
      <%= tabler_ui.icon icon: "star", filled: true, color: "yellow", pulse: true %>
      <%= tabler_ui.icon icon: "refresh", rotate: true %>
      <%= tabler_ui.icon icon: "bell", tada: true %>
      <%= tabler_ui.icon icon: "user", html: { class: "me-2", data: { testid: "user-icon" } } %>
    ERBSRC
    content_5: <<~'ERBSRC',
      <%= tabler_ui.illustration name: "search", size: :sm %>
      <%= tabler_ui.illustration name: "search", theme: "dark", size: :sm %>
    ERBSRC
    content_6: <<~'ERBSRC',
      <%= tabler_ui.status text: "Active", color: "green" %>
      <%= tabler_ui.status text: "Online", color: "green", dot: true %>
      <%= tabler_ui.status text: "Processing", color: "blue", dot: true, animated: true %>
      <%= tabler_ui.status text: "Pending", color: "yellow", light: true %>
      <%= tabler_ui.status color: "green", dot: true, standalone: true %>
      <%= tabler_ui.status color: "red", indicator: true, animated: true %>
    ERBSRC
    content_7: <<~'ERBSRC',
      <%= tabler_ui.progress percent: 42 %>
      <%= tabler_ui.progress percent: 82, color: "auto" %>
      <%= tabler_ui.progress percent: 95, color: "auto" %>
      <%= tabler_ui.progress percent: 60, striped: true, animated: true %>
      <%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
    ERBSRC
    content_8: <<~'ERBSRC',
      <%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart", trend: 12 %>
    ERBSRC
    content_9: <<~'ERBSRC',
      <%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8,
                               description: "vs. last month", url: "#" %>
    ERBSRC
    content_10: <<~'ERBSRC',
      <%= tabler_ui.stat_card label: "Revenue", value: "$9,600", icon: "currency-dollar", color: "green" %>
    ERBSRC
    content_11: <<~'ERBSRC',
      <%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
      <%= tabler_ui.placeholder type: :avatar %>
      <%= tabler_ui.placeholder type: :image, ratio: "21x9" %>
      <%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
      <%= tabler_ui.placeholder type: :text, width: 6, animation: :glow %>
    ERBSRC
    content_12: <<~'ERBSRC',
      <div class="card position-relative">
        <%= tabler_ui.ribbon text: "New", color: "blue" %>
        <div class="card-body">Ribbon pinned to the card's top-right corner.</div>
      </div>
    ERBSRC
    content_13: <<~'ERBSRC',
      <div class="card position-relative">
        <%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start, bookmark: true %>
        <div class="card-body">Bookmark-shaped ribbon, bottom-left.</div>
      </div>
    ERBSRC
    content_14: <<~'ERBSRC',
      <%= tabler_ui.spinner %>
      <%= tabler_ui.spinner type: :grow %>
      <%= tabler_ui.spinner size: "sm", color: "blue" %>
      <%= tabler_ui.spinner label: "Saving..." %>
    ERBSRC
    content_15: <<~'ERBSRC',
      <%= tabler_ui.dimmer active: true do |slots| %>
        <% slots.content do %>
          <div class="p-4">Table rows would render here.</div>
        <% end %>
      <% end %>
    ERBSRC
    content_16: <<~'ERBSRC',
      <%= tabler_ui.empty image: "search", title: "No results found",
                           subtitle: "Try adjusting your search or filter." do |slots| %>
        <% slots.action do %>
          <%= tabler_ui.button text: "Clear filters", url: "#" %>
        <% end %>
      <% end %>
    ERBSRC
    content_17: <<~'ERBSRC',
      <%= tabler_ui.empty icon: "mood-empty", header: "404",
                           title: "Page not found", bordered: true %>
    ERBSRC
    content_18: <<~'ERBSRC',
      <%= tabler_ui.timeline do |t| %>
        <% t.item icon: "check", color: "green" do %>
          <strong>Order placed</strong>
          <div class="text-secondary">2 hours ago</div>
        <% end %>
        <% t.item icon: "truck", color: "blue" do %>
          Shipped
        <% end %>
        <% t.item icon: "flag", color: "red" do %>
          Flagged for review
        <% end %>
      <% end %>
    ERBSRC
    content_19: <<~'ERBSRC',
      <%= tabler_ui.steps(current: 2, counter: true, color: "azure") do |steps| %>
        <% steps.item("Account", url: "#") %>
        <% steps.item("Profile", url: "#") %>
        <% steps.item("Confirm") %>
      <% end %>
    ERBSRC
    content_20: <<~'ERBSRC',
      <%= tabler_ui.breadcrumb(style: :arrows, muted: true) do |breadcrumb| %>
        <% breadcrumb.item("Home", url: "#") %>
        <% breadcrumb.item("Library", url: "#") %>
        <% breadcrumb.item("Data") %>
      <% end %>
    ERBSRC
    content_21: <<~'ERBSRC',
      <%= tabler_ui.pagination current: (params[:page] || 3).to_i, total: 10,
                                url: ->(n) { content_path(page: n) } %>
    ERBSRC
    content_22: <<~'ERBSRC',
      <%= tabler_ui.pagination current: 1, total: 5, url: ->(n) { "?page=#{n}" },
                                size: :sm, circle: true, outline: true %>
    ERBSRC
    content_23: <<~'ERBSRC',
      <%= tabler_ui.rating %>
      <%= tabler_ui.rating choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Ok" }, { value: 3, label: "Great" }],
                            max_stars: 3, color: "yellow", value: 2 %>
    ERBSRC

    overlays_1: <<~'ERBSRC',
      <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#demo-modal">
        Open modal
      </button>

      <%= tabler_ui.modal "demo-modal", title: "Confirm" do |slots| %>
        <% slots.body { "Are you sure you want to continue?" } %>
        <% slots.footer do %>
          <button class="btn btn-link link-secondary" data-bs-dismiss="modal">Cancel</button>
          <%= tabler_ui.button text: "Yes, continue", color: "primary" %>
        <% end %>
      <% end %>
    ERBSRC
    overlays_2: <<~'ERBSRC',
      <button class="btn btn-outline-danger" data-bs-toggle="modal" data-bs-target="#demo-modal-danger">
        Delete item
      </button>

      <%= tabler_ui.modal "demo-modal-danger", title: "Delete item", size: "lg",
                           centered: true, blur: true, status: "danger" do |slots| %>
        <% slots.body { "This action cannot be undone." } %>
      <% end %>
    ERBSRC
    overlays_3: <<~'ERBSRC',
      <button class="btn btn-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas">
        Open filters
      </button>

      <%= tabler_ui.offcanvas "demo-offcanvas", title: "Filters", position: :end do |slots| %>
        <% slots.body { "Filter form goes here." } %>
        <% slots.footer do %>
          <%= tabler_ui.button text: "Apply", color: "primary" %>
        <% end %>
      <% end %>
    ERBSRC
    overlays_4: <<~'ERBSRC',
      <button class="btn btn-outline-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas-bottom">
        Open panel
      </button>

      <%= tabler_ui.offcanvas "demo-offcanvas-bottom", title: "Details", position: :bottom,
                               backdrop: :static do |slots| %>
        <% slots.body { "This offcanvas won't close on backdrop click." } %>
      <% end %>
    ERBSRC
    overlays_5: <<~'ERBSRC',
      <button class="btn btn-success" data-bs-toggle="toast" data-bs-target="#demo-toast">
        Show toast
      </button>

      <div class="toast-container position-fixed bottom-0 end-0 p-3">
        <%= tabler_ui.toast title: "Success", color: "success", html: { id: "demo-toast" } do |slots| %>
          <% slots.body { "Changes saved." } %>
        <% end %>
      </div>
    ERBSRC
    overlays_6: <<~'ERBSRC',
      <button class="btn btn-outline-warning" data-bs-toggle="toast" data-bs-target="#demo-toast-warning">
        Show sticky warning
      </button>

      <%= tabler_ui.toast title: "Heads up", color: "warning", autohide: false,
                           position: "top-right", html: { id: "demo-toast-warning" } do |slots| %>
        <% slots.body { "This toast stays until dismissed." } %>
      <% end %>
    ERBSRC
    overlays_7: <<~'ERBSRC',
      <%= tabler_ui.dropdown(label: "Actions", color: "secondary", align: :end) do |dropdown| %>
        <% dropdown.item("Edit", url: "#", icon: "pencil") %>
        <% dropdown.item("Duplicate", url: "#", icon: "copy") %>
        <% dropdown.divider %>
        <% dropdown.item("Delete", url: "#", icon: "trash") %>
      <% end %>
    ERBSRC
    overlays_8: <<~'ERBSRC',
      <%= tabler_ui.carousel("demo-carousel", indicators: :thumb) do |carousel| %>
        <% carousel.item(image: "https://picsum.photos/id/1015/900/300", caption: "Mountains",
                         caption_background: true, active: true) %>
        <% carousel.item(image: "https://picsum.photos/id/1016/900/300", caption: "Canyon",
                         caption_background: true) %>
        <% carousel.item(image: "https://picsum.photos/id/1018/900/300", caption: "River",
                         caption_background: true) %>
      <% end %>
    ERBSRC

    forms_1: <<~'ERBSRC',
      <%= f.input :name, hint: "Full legal name", required: true %>
    ERBSRC
    forms_2: <<~'ERBSRC',
      <%= f.input :email, label_description: "we'll never share it" %>
    ERBSRC
    forms_3: <<~'ERBSRC',
      <%= f.input :bio, as: :text, input_html: { rows: 3 } %>
    ERBSRC
    forms_4: <<~'ERBSRC',
      <%= f.input :birthday, as: :date_picker %>
    ERBSRC
    forms_5: <<~'ERBSRC',
      <%= f.input :phone %>
    ERBSRC
    forms_6: <<~'ERBSRC',
      <%= f.input :website, as: :floating, label: "Website" %>
    ERBSRC
    forms_7: <<~'ERBSRC',
      <%= f.toggle_switch :newsletter, description: "Product updates, once a month" %>
    ERBSRC
    forms_8: <<~'ERBSRC',
      <%= f.toggle_button :bio_notifications, color: "success", icon: "bell", text: "Notify on profile views" %>
    ERBSRC
    forms_9: <<~'ERBSRC',
      <%= f.input :plan, as: :radio_buttons, collection: %w[free pro enterprise], selectgroup_buttons: true %>
    ERBSRC
    forms_10: <<~'ERBSRC',
      <%= f.input :interests, as: :check_boxes,
                               collection: %w[Design Engineering Marketing Sales], selectgroup_pills: true %>
    ERBSRC
    forms_11: <<~'ERBSRC',
      <%= f.input :role, as: :select, collection: %w[admin editor viewer] %>
    ERBSRC
    forms_12: <<~'ERBSRC',
      <%= f.input :team, as: :grouped_select,
                          collection: { "Engineering" => %w[backend frontend], "Product" => %w[design research] } %>
    ERBSRC
    forms_13: <<~'ERBSRC',
      <%= f.association :manager_id, collection: %w[Alice Bob Carol] %>
    ERBSRC
    forms_14: <<~'ERBSRC',
      <%= f.input :color, as: :color %>
    ERBSRC
    forms_15: <<~'ERBSRC',
      <%= f.input :avatar_rating, as: :rating, max_stars: 5, color: "yellow" %>
    ERBSRC
    forms_16: <<~'ERBSRC',
      <%= f.input :theme, as: :imagecheck, show_text: true,
                           value_method: :id, image_method: :image_url, text_method: :label,
                           collection: [
                             OpenStruct.new(id: "blue", image_url: "https://picsum.photos/seed/blue/80", label: "Blue"),
                             OpenStruct.new(id: "green", image_url: "https://picsum.photos/seed/green/80", label: "Green")
                           ] %>
    ERBSRC
    forms_17: <<~'ERBSRC',
      <%= f.input :resume, as: :file, hint: "PDF, up to 5MB" %>
    ERBSRC
    forms_18: <<~'ERBSRC',
      <%= f.input_field :search_query, input_html: { placeholder: "Naked input, no label/wrapper" } %>
    ERBSRC
    forms_19: <<~'ERBSRC',
      <%= f.input :appointment_at %>
      <%= f.input :salary %>
    ERBSRC
    forms_20: <<~'ERBSRC',
      <%= f.input :salary, as: :input_group, prepend: "$", label: "Salary" %>
      <%= f.input :website, as: :input_group, append: ".com", label: "Website" %>
    ERBSRC
  }.freeze

  def snippet(key)
    ShowcaseHelper::SNIPPETS.fetch(key)
  end
end
