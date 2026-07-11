module Shopify
  # Registers the orders/create webhook subscription via the GraphQL Admin
  # API. Intended to run once at app install (see the shopify:register_webhooks
  # rake task). Safe to re-run: Shopify rejects duplicate topic+address pairs
  # and we treat that as success.
  class WebhookRegistrar
    MUTATION = <<~GRAPHQL
      mutation webhookSubscriptionCreate($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {
        webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
          webhookSubscription { id }
          userErrors { field message }
        }
      }
    GRAPHQL

    def initialize(session: nil)
      @session = session || default_session
    end

    def register_orders_create!
      client = ShopifyAPI::Clients::Graphql::Admin.new(session: @session)
      response = client.query(
        query: MUTATION,
        variables: {
          topic: "ORDERS_CREATE",
          webhookSubscription: {
            callbackUrl: "#{ENV.fetch('APP_HOST')}/webhooks/orders/create",
            format: "JSON"
          }
        }
      )

      errors = response.body.dig("data", "webhookSubscriptionCreate", "userErrors") || []
      real_errors = errors.reject { |e| e["message"].to_s.include?("already been taken") }
      raise "Webhook registration failed: #{real_errors}" if real_errors.any?

      response.body.dig("data", "webhookSubscriptionCreate", "webhookSubscription", "id")
    end

    private

    def default_session
      ShopifyAPI::Auth::Session.new(
        shop: ENV.fetch("SHOPIFY_SHOP_DOMAIN"),
        access_token: ENV.fetch("SHOPIFY_ACCESS_TOKEN")
      )
    end
  end
end
