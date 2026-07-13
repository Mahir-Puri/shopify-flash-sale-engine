# Scheduled with perform_at(starts_at) when the merchant creates the sale.
# Idempotent via FlashSaleActivator's status guard + the NX seed in Redis.
class FlashSaleActivationWorker
  include Sidekiq::Job
  sidekiq_options queue: :critical

  def perform(flash_sale_id)
    flash_sale = FlashSale.find_by(id: flash_sale_id)
    return unless flash_sale

    FlashSaleActivator.new.activate(flash_sale)
  end
end
