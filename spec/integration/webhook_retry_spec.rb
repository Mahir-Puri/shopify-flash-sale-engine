require "rails_helper"

# Shopify retries webhooks aggressively. Three deliveries of the same order
# must produce exactly one confirmed order.
RSpec.describe "Webhook retry simulation", type: :request do
  it "creates one order across three deliveries of the same webhook" do
    sale = create(:flash_sale, :live, inventory_count: 5)
    service = InventoryReservationService.new
    result = service.reserve(flash_sale_id: sale.id, buyer_id: "cust-7")
    create(:reservation, flash_sale: sale, buyer_id: "cust-7", reservation_token: result.token)

    payload = order_payload(shopify_order_id: "7777", variant_id: sale.shopify_variant_id,
                            reservation_token: result.token)

    3.times do
      post_signed_webhook "/webhooks/orders/create", payload
      expect(response).to have_http_status(:ok)
      OrderWebhookWorker.drain
    end

    expect(Order.where(shopify_order_id: "7777").count).to eq(1)
    expect(WebhookEvent.where(shopify_order_id: "7777").count).to eq(1)
    expect(Reservation.find_by(reservation_token: result.token)).to be_confirmed
    expect(service.current_inventory(sale.id)).to eq(4)
  end
end
