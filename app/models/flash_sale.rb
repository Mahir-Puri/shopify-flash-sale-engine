class FlashSale < ApplicationRecord
  has_many :reservations, dependent: :destroy

  enum :status, { scheduled: "scheduled", active: "active", ended: "ended" }, default: :scheduled

  validates :shopify_product_id, :shopify_variant_id, :starts_at, presence: true
  validates :inventory_count, numericality: { only_integer: true, greater_than: 0 }
  validates :reservation_timeout_seconds, numericality: { only_integer: true, greater_than: 0 }

  scope :active_for_variant, ->(variant_id) { active.where(shopify_variant_id: variant_id.to_s) }

  def inventory_key
    "flash_sale:#{id}:inventory"
  end

  def config_key
    "flash_sale:#{id}:config"
  end

  def reservation_key(buyer_id)
    "flash_sale:#{id}:reservation:#{buyer_id}"
  end
end
