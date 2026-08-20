# frozen_string_literal: true

class ShowcaseController < ActionController::Base
  layout "application"

  def index; end

  def layout
    @table_demo_sort = table_demo_sort
    @table_demo_page = table_demo_page
    @table_demo_total_pages = table_demo_total_pages
    @table_demo_rows = table_demo_rows
  end

  def content; end

  def overlays; end

  def forms
    @person = PersonForm.new(
      name: "Ada Lovelace",
      email: "ada@example.com",
      bio: "Mathematician and writer, chiefly known for her work on Charles Babbage's Analytical Engine.",
      birthday: Date.new(1815, 12, 10),
      appointment_at: Time.zone.local(2026, 9, 1, 14, 30),
      salary: 1234.56,
      website: "https://example.com",
      phone: "+1 555 0100",
      newsletter: true,
      bio_notifications: true,
      plan: "pro",
      role: "admin",
      team: "backend",
      interests: ["Engineering"],
      color: "#4299e1",
      theme: "blue",
      avatar_rating: 4,
      manager_id: "Alice",
      resume: nil,
      search_query: nil
    )
    @person.valid?
    @person.errors.add(:email, "is already taken") if params[:with_errors]
  end

  private

  # Sortable/filterable table demo data (layout page, "table - sorting and
  # filtering" example). A plain hardcoded array, no ORM -- per the table
  # component's class docs, sorting/filtering are entirely this controller's
  # job; the component only renders links and a form against whatever state
  # it's handed.
  TABLE_DEMO_ROWS = [
    { name: "Ada Lovelace", status: "active", created_at: Date.new(2026, 1, 12) },
    { name: "Grace Hopper", status: "active", created_at: Date.new(2025, 11, 3) },
    { name: "Alan Turing", status: "away", created_at: Date.new(2026, 2, 20) },
    { name: "Katherine Johnson", status: "active", created_at: Date.new(2025, 8, 30) },
    { name: "Margaret Hamilton", status: "inactive", created_at: Date.new(2026, 3, 5) },
    { name: "Radia Perlman", status: "away", created_at: Date.new(2025, 12, 18) },
    { name: "Barbara Liskov", status: "active", created_at: Date.new(2026, 4, 1) }
  ].freeze

  # Whitelist of the columns the demo actually lets a caller sort by -- a
  # column that isn't in this list (or a junk params[:sort]) is treated as
  # "no sort" rather than passed through to Array#sort_by/blowing up.
  TABLE_DEMO_SORT_KEYS = %w[name status created_at].freeze

  # Rows per page for the frame:/pagination demo -- deliberately small (the
  # fixture has 7 rows) so the demo actually spans multiple pages.
  TABLE_DEMO_PER_PAGE = 3

  # @return [Hash] { key:, dir: } built from params, both whitelisted: key
  # is nil unless it names an actual sortable column, dir collapses to
  # "asc" unless it's exactly "desc". Reused for the row sort itself, the
  # component's sort:, and every sort_url:/hidden: link built in the view,
  # so a junk ?sort=/?dir= in the URL can never reach the table component
  # (which raises ArgumentError on an unrecognised dir:) or Array#sort_by.
  def table_demo_sort
    key = params[:sort] if TABLE_DEMO_SORT_KEYS.include?(params[:sort])
    { key: key, dir: params[:dir] == "desc" ? "desc" : "asc" }
  end

  # @return [Array<Hash>] the current page's rows -- filtered, then sorted,
  # then sliced. Paging never touches the filter/sort itself, exactly like
  # sorting never touches the filter -- each stage only sees the previous
  # stage's output.
  def table_demo_rows
    rows = sort_table_demo_rows(table_demo_filtered_rows)
    offset = (table_demo_page - 1) * TABLE_DEMO_PER_PAGE
    rows[offset, TABLE_DEMO_PER_PAGE] || []
  end

  # @return [Array<Hash>] TABLE_DEMO_ROWS after filter_table_demo_rows --
  # split out from #table_demo_rows so #table_demo_total_pages can count the
  # filtered set without also sorting/slicing it.
  def table_demo_filtered_rows
    filter_table_demo_rows(TABLE_DEMO_ROWS)
  end

  # @return [Integer] total pages for the *filtered* row count (never less
  # than 1, even when the filter matches nothing, so pagination's
  # total: 0 vs total: 1 degenerate cases -- see its class docs -- never see
  # a 0 here).
  def table_demo_total_pages
    [(table_demo_filtered_rows.size / TABLE_DEMO_PER_PAGE.to_f).ceil, 1].max
  end

  # @return [Integer] the current page, clamped to 1..table_demo_total_pages.
  # `params[:page]` is never trusted directly -- a junk value ("abc") coerces
  # to 0 via #to_i and clamps to 1; an out-of-range value ("999") clamps to
  # the last real page -- either way this never reaches the pagination
  # component's current: with an out-of-range value (which raises
  # ArgumentError -- see its class docs' "Degenerate totals" section).
  def table_demo_page
    page = params[:page].to_i
    return 1 if page < 1

    [page, table_demo_total_pages].min
  end

  def filter_table_demo_rows(rows)
    if params[:q].present?
      term = params[:q].downcase
      rows = rows.select { |row| row[:name].downcase.include?(term) }
    end
    rows = rows.select { |row| row[:status] == params[:status] } if params[:status].present?
    rows
  end

  def sort_table_demo_rows(rows)
    return rows unless @table_demo_sort[:key]

    sorted = rows.sort_by { |row| row[@table_demo_sort[:key].to_sym] }
    @table_demo_sort[:dir] == "desc" ? sorted.reverse : sorted
  end

  # A plain ActiveModel double -- no database, per the brief.
  #
  # NOTE: TablerUi::FormBuilder#input infers a field's widget from
  # @object.type_for_attribute / #has_attribute?, both ActiveRecord instance
  # methods. ActiveModel::Attributes only defines type_for_attribute at the
  # CLASS level (see ActiveModel::AttributeRegistration::ClassMethods), so on
  # a plain ActiveModel::Model instance `respond_to?(:type_for_attribute)` is
  # false and EVERY field -- including :integer/:decimal/:datetime/:time
  # columns -- silently falls back to a plain text input; those four types
  # have no dedicated `as:` value either (only :date has :date_picker),
  # so there is no way to reach their specialised widgets at all without a
  # real ActiveRecord-backed object. Confirmed with `bundle exec ruby`, see
  # showcase build report. Worked around here with explicit `as:` wherever a
  # value exists (:date_picker, :rating, ...); appointment_at/salary are left
  # as plain text on purpose, to demonstrate the gap.
  class PersonForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :name, :string
    attribute :email, :string
    attribute :bio, :string
    attribute :birthday, :date
    attribute :appointment_at, :datetime
    attribute :salary, :decimal
    attribute :website, :string
    attribute :phone, :string
    attribute :newsletter, :boolean
    attribute :bio_notifications, :boolean
    attribute :plan, :string
    attribute :role, :string
    attribute :team, :string
    attribute :interests, default: -> { [] }
    attribute :color, :string
    attribute :theme, :string
    attribute :avatar_rating, :integer
    attribute :manager_id, :string
    attribute :resume
    attribute :search_query, :string

    validates :name, presence: true
  end
end
