class DashboardController < ApplicationController
  RECENT_LIMIT = 50

  # GET /dashboard
  def show
    service = InventoryReservationService.new

    render json: {
      active_flash_sales: FlashSale.active.map { |sale|
        {
          id: sale.id,
          shopify_variant_id: sale.shopify_variant_id,
          configured_inventory: sale.inventory_count,
          live_inventory: service.current_inventory(sale.id),
          starts_at: sale.starts_at.iso8601
        }
      },
      recent_reservations: Reservation.order(created_at: :desc).limit(RECENT_LIMIT).map { |r|
        {
          id: r.id,
          flash_sale_id: r.flash_sale_id,
          buyer_id: r.buyer_id,
          status: r.status,
          expires_at: r.expires_at.iso8601,
          created_at: r.created_at.iso8601
        }
      },
      webhook_events: WebhookEvent.order(created_at: :desc).limit(RECENT_LIMIT).map { |e|
        {
          id: e.id,
          shopify_order_id: e.shopify_order_id,
          status: e.status,
          processed_at: e.processed_at&.iso8601,
          received_at: e.created_at.iso8601
        }
      }
    }
  end
end
