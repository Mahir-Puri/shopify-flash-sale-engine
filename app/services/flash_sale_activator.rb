# Moves a sale from scheduled -> active. Seeding Redis happens before the
# status flip so that the moment /reserve starts returning successes, the
# counter is guaranteed to exist. Idempotent end to end: the Redis SET is NX
# and the status guard makes a re-run a no-op.
class FlashSaleActivator
  def initialize(reservation_service: InventoryReservationService.new)
    @reservation_service = reservation_service
  end

  def activate(flash_sale)
    return flash_sale unless flash_sale.scheduled?

    @reservation_service.activate(flash_sale)
    flash_sale.update!(status: :active)
    flash_sale
  end
end
