FactoryBot.define do
  factory :webhook_event do
    sequence(:shopify_order_id) { |n| "order-#{n}" }
    payload { {} }
    status { "received" }
  end
end
