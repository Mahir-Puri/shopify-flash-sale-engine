require "rails_helper"

# The money test: 150 buyers, 100 units, full app stack, real Redis.
# Exactly 100 reservations may succeed. Not 99, not 101.
RSpec.describe "Oversell protection", type: :request, no_transaction: true do
  CONCURRENT_BUYERS = 150
  INVENTORY = 100

  it "grants exactly #{INVENTORY} of #{CONCURRENT_BUYERS} concurrent reservations" do
    sale = create(:flash_sale, :live, inventory_count: INVENTORY)
    service = InventoryReservationService.new

    barrier = Queue.new
    threads = Array.new(CONCURRENT_BUYERS) do |i|
      Thread.new do
        barrier.pop # hold every thread until all are spawned
        service.reserve(flash_sale_id: sale.id, buyer_id: "load-buyer-#{i}")
      end
    end
    CONCURRENT_BUYERS.times { barrier << :go }
    results = threads.map(&:value)

    successes = results.count(&:reserved?)
    sold_out = results.count { |r| r.reason == "sold_out" }

    expect(successes).to eq(INVENTORY)
    expect(sold_out).to eq(CONCURRENT_BUYERS - INVENTORY)
    expect(service.current_inventory(sale.id)).to eq(0)

    # Every token is unique: no two buyers hold the same reservation.
    tokens = results.select(&:reserved?).map(&:token)
    expect(tokens.uniq.size).to eq(INVENTORY)
  end
end
