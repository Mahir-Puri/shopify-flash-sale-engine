require "rails_helper"

RSpec.describe "Api::FlashSales", type: :request do
  describe "POST /api/flash_sales" do
    it "creates a sale and schedules activation" do
      post "/api/flash_sales", params: {
        product_id: "prod-1",
        shopify_variant_id: "var-1",
        inventory_count: 100,
        starts_at: 1.hour.from_now.iso8601,
        reservation_timeout_seconds: 180
      }

      expect(response).to have_http_status(:created)
      sale = FlashSale.last
      expect(sale.shopify_product_id).to eq("prod-1")
      expect(sale).to be_scheduled
      expect(FlashSaleActivationWorker.jobs.size).to eq(1)
      expect(FlashSaleActivationWorker.jobs.first["at"]).to be_within(5).of(1.hour.from_now.to_f)
    end

    it "rejects invalid input" do
      post "/api/flash_sales", params: { product_id: "prod-1" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/flash_sales/:id/reserve" do
    let(:flash_sale) { create(:flash_sale, :live, inventory_count: 1, reservation_timeout_seconds: 60) }

    it "reserves and enqueues recorder + expiry jobs" do
      post "/api/flash_sales/#{flash_sale.id}/reserve", params: { buyer_id: "buyer-1" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["reserved"]).to be(true)
      expect(body["reservation_token"]).to be_present

      expect(ReservationRecorderWorker.jobs.size).to eq(1)
      expect(ReservationExpiryWorker.jobs.size).to eq(1)
      expect(ReservationExpiryWorker.jobs.first["at"]).to be_within(5).of(60.seconds.from_now.to_f)
    end

    it "returns 409 sold_out at zero inventory" do
      post "/api/flash_sales/#{flash_sale.id}/reserve", params: { buyer_id: "buyer-1" }
      post "/api/flash_sales/#{flash_sale.id}/reserve", params: { buyer_id: "buyer-2" }

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["reason"]).to eq("sold_out")
    end

    it "returns 422 not_active for a sale that has not started" do
      inactive = create(:flash_sale)
      post "/api/flash_sales/#{inactive.id}/reserve", params: { buyer_id: "buyer-1" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["reason"]).to eq("not_active")
    end
  end
end
