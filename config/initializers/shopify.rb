# Configured lazily: the app boots fine without Shopify credentials (local dev,
# CI, load testing). Real webhook registration only happens when an API key,
# secret, and shop domain are present. HMAC verification of inbound webhooks
# needs only SHOPIFY_WEBHOOK_SECRET.
if ENV["SHOPIFY_API_KEY"].present? && ENV["SHOPIFY_API_SECRET"].present?
  ShopifyAPI::Context.setup(
    api_key: ENV["SHOPIFY_API_KEY"],
    api_secret_key: ENV["SHOPIFY_API_SECRET"],
    host: ENV.fetch("APP_HOST", "http://localhost:3000"),
    scope: "read_orders,read_products",
    is_embedded: false,
    is_private: false,
    api_version: "2025-01"
  )
end
