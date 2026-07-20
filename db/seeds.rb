# Seeds one demo flash sale that is live immediately, so `docker-compose up`
# gives you something to hit with the load test without any Shopify setup.
sale = FlashSale.find_or_create_by!(shopify_product_id: "demo-product-1", shopify_variant_id: "demo-variant-1") do |s|
  s.inventory_count = 100
  s.starts_at = Time.current
  s.reservation_timeout_seconds = 300
end

if sale.scheduled?
  FlashSaleActivator.new.activate(sale)
  puts "Activated demo flash sale ##{sale.id} with #{sale.inventory_count} units."
else
  puts "Demo flash sale ##{sale.id} already #{sale.status}."
end
