class Reservation < ApplicationRecord
  belongs_to :flash_sale
  has_one :order, dependent: :destroy

  enum :status, { pending: "pending", confirmed: "confirmed", expired: "expired" }, default: :pending

  validates :buyer_id, :reservation_token, :expires_at, presence: true
  validates :reservation_token, uniqueness: true
end
