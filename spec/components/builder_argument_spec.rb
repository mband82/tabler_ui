require "rails_helper"

# Rule 4 moved builder methods from keyword args (`item(title: "x")`) to
# positionals (`item("x")`). Ruby collapses a stale keyword call into a Hash
# and binds it to the positional silently, rendering `{title: "x"}` as content.
# TablerUi::Base#builder_argument! turns that into a clear error instead.
RSpec.describe "builder positional-argument guard", type: :component do
  it "raises a helpful error when settings_page#item is called the old way" do
    expect {
      render_component(:settings_page, id: "s1") { |sp| sp.item(title: "General") }
    }.to raise_error(ArgumentError, /settings_page#item takes title positionally/)
  end

  it "raises a helpful error when datagrid#item is called the old way" do
    expect {
      render_component(:datagrid) { |dg| dg.item(title: "Name") }
    }.to raise_error(ArgumentError, /datagrid#item takes title positionally/)
  end

  it "raises a helpful error when tabs#tab is called the old way" do
    expect {
      render_component(:tabs, id: "t1") { |tabs| tabs.tab(title: "First") }
    }.to raise_error(ArgumentError, /tabs#tab takes title positionally/)
  end

  it "accepts the positional form" do
    html = render_component(:datagrid) { |dg| dg.item("Name", content: "Value") }
    expect(html).to include("Name", "Value")
  end
end
