FactoryBot.define do
  factory :reservation do
    flash_sale
    sequence(:buyer_id) { |n| "buyer-#{n}" }
    reservation_token { SecureRandom.uuid }
    status { "pending" }
    expires_at { 5.minutes.from_now }
  end
end
