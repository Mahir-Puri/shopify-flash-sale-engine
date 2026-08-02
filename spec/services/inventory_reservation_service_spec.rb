require "rails_helper"

RSpec.describe InventoryReservationService do
  subject(:service) { described_class.new }

  let(:flash_sale) { create(:flash_sale, :live, inventory_count: 2, reservation_timeout_seconds: 120) }

  describe "#reserve" do
    it "reserves a unit, returns a token, and decrements inventory" do
      result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      expect(result).to be_reserved
      expect(result.token).to match(/\A[0-9a-f-]{36}\z/)
      expect(result.timeout_seconds).to eq(120)
      expect(service.current_inventory(flash_sale.id)).to eq(1)
    end

    it "sets a TTL with grace on the reservation key" do
      service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      ttl = RedisConnection.client.ttl(flash_sale.reservation_key("buyer-1"))
      expect(ttl).to be_between(120, 120 + described_class::TTL_GRACE_SECONDS)
    end

    it "rejects a sale that was never activated" do
      inactive = create(:flash_sale)
      result = service.reserve(flash_sale_id: inactive.id, buyer_id: "buyer-1")

      expect(result).not_to be_reserved
      expect(result.reason).to eq("not_active")
    end

    it "rejects a second reservation from the same buyer" do
      service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
      result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      expect(result).not_to be_reserved
      expect(result.reason).to eq("already_reserved")
      expect(service.current_inventory(flash_sale.id)).to eq(1)
    end

    it "sells exactly to the boundary and no further" do
      r1 = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
      r2 = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-2")
      r3 = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-3")

      expect([r1, r2].map(&:reserved?)).to all(be true)
      expect(r3).not_to be_reserved
      expect(r3.reason).to eq("sold_out")
      expect(service.current_inventory(flash_sale.id)).to eq(0)
    end

    it "never oversells under concurrent decrements", :no_transaction do
      sale = create(:flash_sale, :live, inventory_count: 10)

      results = Array.new(50) { |i|
        Thread.new { service.reserve(flash_sale_id: sale.id, buyer_id: "buyer-#{i}") }
      }.map(&:value)

      expect(results.count(&:reserved?)).to eq(10)
      expect(service.current_inventory(sale.id)).to eq(0)
    end
  end

  describe "#release" do
    it "restores inventory when the token still matches" do
      result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      released = service.release(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: result.token)

      expect(released).to be(true)
      expect(service.current_inventory(flash_sale.id)).to eq(2)
    end

    it "does nothing when the reservation was already confirmed" do
      result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
      service.confirm(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: result.token)

      released = service.release(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: result.token)

      expect(released).to be(false)
      expect(service.current_inventory(flash_sale.id)).to eq(1)
    end

    it "does nothing when the token does not match" do
      service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      released = service.release(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: "forged")

      expect(released).to be(false)
      expect(service.current_inventory(flash_sale.id)).to eq(1)
    end
  end

  describe "#confirm" do
    it "consumes the reservation without restoring inventory" do
      result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")

      confirmed = service.confirm(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: result.token)

      expect(confirmed).to be(true)
      expect(service.current_inventory(flash_sale.id)).to eq(1)
      expect(RedisConnection.client.exists(flash_sale.reservation_key("buyer-1"))).to eq(0)
    end
  end

  describe "#activate" do
    it "is idempotent: a second activation cannot reset the counter" do
      service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
      service.activate(flash_sale)

      expect(service.current_inventory(flash_sale.id)).to eq(1)
    end
  end
end
