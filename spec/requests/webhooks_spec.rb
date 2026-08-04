require "rails_helper"

RSpec.describe "Webhooks::Orders", type: :request do
  let(:flash_sale) { create(:flash_sale, :live) }
  let(:payload) { order_payload(shopify_order_id: "5001", variant_id: flash_sale.shopify_variant_id) }

  describe "HMAC verification" do
    it "returns 200 for a valid signature and records the event" do
      post_signed_webhook "/webhooks/orders/create", payload

      expect(response).to have_http_status(:ok)
      expect(WebhookEvent.find_by(shopify_order_id: "5001")).to be_present
      expect(OrderWebhookWorker.jobs.size).to eq(1)
    end

    it "returns 401 for a tampered payload and touches nothing" do
      raw = payload.to_json
      hmac = shopify_hmac(raw)
      post "/webhooks/orders/create",
           params: raw.sub("5001", "6001"),
           headers: { "CONTENT_TYPE" => "application/json", "X-Shopify-Hmac-SHA256" => hmac }

      expect(response).to have_http_status(:unauthorized)
      expect(WebhookEvent.count).to eq(0)
      expect(OrderWebhookWorker.jobs).to be_empty
    end

    it "returns 401 when the header is missing" do
      post "/webhooks/orders/create", params: payload.to_json,
                                      headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "idempotency" do
    it "creates one event for duplicate deliveries and short-circuits once processed" do
      2.times { post_signed_webhook "/webhooks/orders/create", payload }
      expect(WebhookEvent.where(shopify_order_id: "5001").count).to eq(1)

      WebhookEvent.find_by(shopify_order_id: "5001").update!(status: :processed, processed_at: Time.current)
      OrderWebhookWorker.clear

      post_signed_webhook "/webhooks/orders/create", payload

      expect(response).to have_http_status(:ok)
      expect(OrderWebhookWorker.jobs).to be_empty
    end
  end
end
