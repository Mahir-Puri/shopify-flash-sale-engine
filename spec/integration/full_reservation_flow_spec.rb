require "rails_helper"

# End to end against real Redis and real Postgres:
# configure -> activate -> reserve -> confirm via webhook -> expiry no-op.
RSpec.describe "Full reservation flow", type: :request do
  it "walks a unit from configuration to confirmed order" do
    # 1. Merchant configures a sale that starts immediately.
    post "/api/flash_sales", params: {
      product_id: "prod-9",
      shopify_variant_id: "var-9",
      inventory_count: 3,
      starts_at: Time.current.iso8601,
      reservation_timeout_seconds: 120
    }
    expect(response).to have_http_status(:created)
    sale_id = JSON.parse(response.body)["id"]

    # 2. Activation job seeds Redis and flips status.
    FlashSaleActivationWorker.drain
    sale = FlashSale.find(sale_id)
    expect(sale).to be_active
    service = InventoryReservationService.new
    expect(service.current_inventory(sale_id)).to eq(3)

    # 3. Buyer reserves.
    post "/api/flash_sales/#{sale_id}/reserve", params: { buyer_id: "cust-42" }
    token = JSON.parse(response.body)["reservation_token"]
    expect(token).to be_present
    expect(service.current_inventory(sale_id)).to eq(2)

    ReservationRecorderWorker.drain
    reservation = Reservation.find_by(reservation_token: token)
    expect(reservation).to be_pending

    # 4. Shopify delivers orders/create; worker confirms the reservation.
    payload = order_payload(shopify_order_id: "9001", variant_id: "var-9",
                            reservation_token: token, customer_id: "cust-42")
    post_signed_webhook "/webhooks/orders/create", payload
    expect(response).to have_http_status(:ok)
    OrderWebhookWorker.drain

    expect(reservation.reload).to be_confirmed
    order = Order.find_by(shopify_order_id: "9001")
    expect(order.reservation).to eq(reservation)
    expect(WebhookEvent.find_by(shopify_order_id: "9001")).to be_processed

    # 5. The scheduled expiry job fires later and must NOT restore inventory.
    ReservationExpiryWorker.drain
    expect(service.current_inventory(sale_id)).to eq(2)
    expect(reservation.reload).to be_confirmed
  end

  it "restores inventory when the buyer walks away" do
    sale = create(:flash_sale, :live, inventory_count: 3)
    service = InventoryReservationService.new

    post "/api/flash_sales/#{sale.id}/reserve", params: { buyer_id: "ghost-1" }
    expect(service.current_inventory(sale.id)).to eq(2)

    ReservationRecorderWorker.drain
    ReservationExpiryWorker.drain # simulate the timeout elapsing

    expect(service.current_inventory(sale.id)).to eq(3)
    expect(Reservation.find_by(buyer_id: "ghost-1")).to be_expired
  end
end
