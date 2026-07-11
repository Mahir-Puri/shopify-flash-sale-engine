class WebhookEvent < ApplicationRecord
  enum :status, { received: "received", processed: "processed", failed: "failed" }, default: :received

  validates :shopify_order_id, presence: true, uniqueness: true
end
