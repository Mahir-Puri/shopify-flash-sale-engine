# Fires exactly reservation_timeout_seconds after a reservation is made.
# The release script only restores inventory when the Redis key still holds
# our token, so racing against a webhook confirmation is safe: whichever
# side deletes the key first wins, and the other becomes a no-op.
class ReservationExpiryWorker
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform(flash_sale_id, buyer_id, token)
    released = InventoryReservationService.new.release(
      flash_sale_id: flash_sale_id,
      buyer_id: buyer_id,
      token: token
    )
    return unless released

    reservation = Reservation.find_by(reservation_token: token)
    reservation&.pending? && reservation.update!(status: :expired)
  end
end
