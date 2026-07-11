# Runs inside OrderWebhookWorker. Takes a parsed Shopify order payload and
# confirms the matching reservation.
#
# Reservation lookup order:
#   1. reservation_token in the order's note_attributes (the storefront is
#      expected to attach the token returned by /reserve as a cart attribute)
#   2. fallback: the pending reservation for (active sale on this variant,
#      buyer_id = Shopify customer id)
#
# The Redis confirm happens after the Postgres transaction commits. Worst
# case on a crash between the two: Postgres says confirmed, the Redis key
# lives until the expiry worker fires, the token comparison in RELEASE still
# matches, and one unit gets restored for a sale that happened. That is an
# oversell-by-one risk only in the crash window, and re-running the worker
# (Sidekiq retries on raise) closes it. The reverse ordering would risk
# losing the confirmation entirely, which is worse.
class OrderConfirmationService
  def initialize(reservation_service: InventoryReservationService.new)
    @reservation_service = reservation_service
  end

  def confirm_order(payload)
    token = extract_token(payload)
    buyer_id = payload.dig("customer", "id")&.to_s

    Array(payload["line_items"]).each do |line_item|
      variant_id = line_item["variant_id"]&.to_s
      next if variant_id.blank?

      FlashSale.active_for_variant(variant_id).find_each do |sale|
        reservation = find_reservation(sale, token, buyer_id)
        next unless reservation

        confirm(reservation, payload, line_item)
      end
    end
  end

  private

  def extract_token(payload)
    attrs = Array(payload["note_attributes"])
    attrs.find { |a| a["name"] == "reservation_token" }&.fetch("value", nil)
  end

  def find_reservation(sale, token, buyer_id)
    if token.present?
      sale.reservations.find_by(reservation_token: token)
    elsif buyer_id.present?
      sale.reservations.pending.find_by(buyer_id: buyer_id)
    end
  end

  def confirm(reservation, payload, line_item)
    return if reservation.confirmed?

    ActiveRecord::Base.transaction do
      reservation.lock!
      return if reservation.confirmed?

      reservation.update!(status: :confirmed)
      Order.create!(
        reservation: reservation,
        shopify_order_id: payload["id"].to_s,
        line_items: [line_item]
      )
    end

    # Deletes the Redis reservation key so the expiry worker becomes a no-op.
    @reservation_service.confirm(
      flash_sale_id: reservation.flash_sale_id,
      buyer_id: reservation.buyer_id,
      token: reservation.reservation_token
    )
  end
end
