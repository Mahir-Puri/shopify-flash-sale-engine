class Order < ApplicationRecord
  belongs_to :reservation

  validates :shopify_order_id, presence: true, uniqueness: true
end
