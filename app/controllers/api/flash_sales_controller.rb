module Api
  class FlashSalesController < ApplicationController
    # POST /api/flash_sales
    def create
      flash_sale = FlashSale.create!(flash_sale_params)

      if flash_sale.starts_at <= Time.current
        FlashSaleActivationWorker.perform_async(flash_sale.id)
      else
        FlashSaleActivationWorker.perform_at(flash_sale.starts_at, flash_sale.id)
      end

      render json: flash_sale_json(flash_sale), status: :created
    end

    # GET /api/flash_sales/:id
    def show
      flash_sale = FlashSale.find(params[:id])
      render json: flash_sale_json(flash_sale)
    end

    # POST /api/flash_sales/:id/reserve
    #
    # The hot path. Note what is absent: no FlashSale.find, no Reservation
    # row, no transaction. One Lua script and (on success) two Sidekiq
    # enqueues, all of which are Redis operations.
    def reserve
      buyer_id = params.require(:buyer_id).to_s
      flash_sale_id = params[:id].to_i

      result = reservation_service.reserve(flash_sale_id: flash_sale_id, buyer_id: buyer_id)

      unless result.reserved?
        return render json: { reserved: false, reason: result.reason },
                      status: status_for(result.reason)
      end

      expires_at = Time.current + result.timeout_seconds
      ReservationRecorderWorker.perform_async(flash_sale_id, buyer_id, result.token, expires_at.to_i)
      ReservationExpiryWorker.perform_in(result.timeout_seconds, flash_sale_id, buyer_id, result.token)

      render json: {
        reserved: true,
        reservation_token: result.token,
        expires_at: expires_at.iso8601
      }
    end

    private

    def flash_sale_params
      params.permit(:shopify_product_id, :product_id, :shopify_variant_id,
                    :inventory_count, :starts_at, :reservation_timeout_seconds)
            .to_h
            .then { |h| product_id = h.delete("product_id"); h["shopify_product_id"] ||= product_id; h }
    end

    def flash_sale_json(sale)
      {
        id: sale.id,
        shopify_product_id: sale.shopify_product_id,
        shopify_variant_id: sale.shopify_variant_id,
        inventory_count: sale.inventory_count,
        starts_at: sale.starts_at.iso8601,
        reservation_timeout_seconds: sale.reservation_timeout_seconds,
        status: sale.status
      }
    end

    def reservation_service
      @reservation_service ||= InventoryReservationService.new
    end

    def status_for(reason)
      case reason
      when "sold_out"         then :conflict
      when "already_reserved" then :conflict
      when "not_active"       then :unprocessable_entity
      else :unprocessable_entity
      end
    end
  end
end
