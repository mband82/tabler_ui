# frozen_string_literal: true

class ShowcaseController < ActionController::Base
  layout "application"

  def index; end

  def layout; end

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
