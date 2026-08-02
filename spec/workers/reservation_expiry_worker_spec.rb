require "rails_helper"

RSpec.describe ReservationExpiryWorker do
  let(:service) { InventoryReservationService.new }
  let(:flash_sale) { create(:flash_sale, :live, inventory_count: 5) }

  it "restores inventory and marks a still-pending reservation expired" do
    result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
    reservation = create(:reservation, flash_sale:, buyer_id: "buyer-1", reservation_token: result.token)

    described_class.new.perform(flash_sale.id, "buyer-1", result.token)

    expect(service.current_inventory(flash_sale.id)).to eq(5)
    expect(reservation.reload).to be_expired
  end

  it "is a no-op when the reservation was confirmed first" do
    result = service.reserve(flash_sale_id: flash_sale.id, buyer_id: "buyer-1")
    reservation = create(:reservation, flash_sale:, buyer_id: "buyer-1",
                                       reservation_token: result.token, status: "confirmed")
    service.confirm(flash_sale_id: flash_sale.id, buyer_id: "buyer-1", token: result.token)

    described_class.new.perform(flash_sale.id, "buyer-1", result.token)

    expect(service.current_inventory(flash_sale.id)).to eq(4)
    expect(reservation.reload).to be_confirmed
  end
end
