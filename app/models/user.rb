class User < ApplicationRecord
  include Accessor, ActionText::Attachable, Assignee, Mentionable, Named, Role, Searcher,
    SignalUser, Transferable
  include Timelined # Depends on Accessor

  has_one_attached :avatar

  has_many :sessions, dependent: :destroy
  has_secure_password validations: false

  has_many :comments, inverse_of: :creator, dependent: :destroy

  has_many :notifications, dependent: :destroy

  has_many :filters, foreign_key: :creator_id, inverse_of: :creator, dependent: :destroy
  has_many :closures, dependent: :nullify
  has_many :pins, dependent: :destroy
  has_many :pinned_cards, through: :pins, source: :card
  has_many :commands, dependent: :destroy

  normalizes :email_address, with: ->(value) { value.strip.downcase }

  def deactivate
    sessions.delete_all
    accesses.destroy_all
    update! active: false, email_address: deactived_email_address
  end

  # TODO: Move to attachable along with the concern
  def attachable_plain_text_representation(...)
    "@#{first_name.downcase}"
  end

  private
    def deactived_email_address
      email_address.sub(/@/, "-deactivated-#{SecureRandom.uuid}@")
    end
end
