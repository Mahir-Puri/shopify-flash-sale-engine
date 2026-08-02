FactoryBot.define do
  factory :flash_sale do
    sequence(:shopify_product_id) { |n| "product-#{n}" }
    sequence(:shopify_variant_id) { |n| "variant-#{n}" }
    inventory_count { 100 }
    starts_at { Time.current }
    reservation_timeout_seconds { 300 }
    status { "scheduled" }

    trait :active do
      status { "active" }
    end

    # Active in Postgres AND seeded in Redis, i.e. genuinely live.
    trait :live do
      status { "scheduled" }
      after(:create) { |sale| FlashSaleActivator.new.activate(sale) }
    end
  end
end
