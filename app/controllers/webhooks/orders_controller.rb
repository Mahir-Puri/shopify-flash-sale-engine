module Webhooks
  class OrdersController < ApplicationController
    # POST /webhooks/orders/create
    #
    # Order of operations is deliberate and matches the architecture rules:
    #   1. HMAC over the raw body, before parsing, before any DB access.
    #   2. Idempotency check on shopify_order_id.
    #   3. Enqueue async processing.
    #   4. Return 200 synchronously so Shopify does not retry.
    def create
      raw = request.raw_post
      hmac = request.headers["X-Shopify-Hmac-SHA256"]
      return head :unauthorized unless WebhookVerifier.valid?(raw, hmac)

      payload = JSON.parse(raw)
      shopify_order_id = payload["id"].to_s
      return head :bad_request if shopify_order_id.blank?

      event = WebhookEvent.find_by(shopify_order_id: shopify_order_id)
      return head :ok if event&.processed?

      event ||= create_event(shopify_order_id, payload)
      OrderWebhookWorker.perform_async(event.id) if event

      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    # Two deliveries of the same order can race past the find_by above; the
    # unique index makes exactly one INSERT win. The loser re-reads the row
    # and (at worst) enqueues a duplicate job, which the worker's row lock
    # and processed? guard turn into a no-op.
    def create_event(shopify_order_id, payload)
      WebhookEvent.create!(shopify_order_id: shopify_order_id, payload: payload)
    rescue ActiveRecord::RecordNotUnique
      WebhookEvent.find_by(shopify_order_id: shopify_order_id)
    end
  end
end
