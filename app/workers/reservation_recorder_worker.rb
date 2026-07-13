# Persists the Postgres row for a reservation that already exists in Redis.
# This is how the hot path stays database-free: the controller enqueues this
# job (a Redis LPUSH under the hood) and returns; the row is written moments
# later off the request thread. find_or_create_by keeps retries idempotent.
class ReservationRecorderWorker
  include Sidekiq::Job
  sidekiq_options queue: :critical

  def perform(flash_sale_id, buyer_id, token, expires_at_epoch)
    Reservation.find_or_create_by!(reservation_token: token) do |r|
      r.flash_sale_id = flash_sale_id
      r.buyer_id = buyer_id
      r.status = :pending
      r.expires_at = Time.zone.at(expires_at_epoch)
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent retry already wrote it. Done.
  end
end
