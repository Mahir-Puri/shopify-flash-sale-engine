namespace :shopify do
  desc "Register the orders/create webhook subscription with Shopify"
  task register_webhooks: :environment do
    id = Shopify::WebhookRegistrar.new.register_orders_create!
    puts "Registered orders/create webhook: #{id}"
  end
end
