# All webhook business logic lives here, off the HTTP thread. The controller
# has already verified the HMAC and created the webhook_events row; this
# worker is free to take its time, retry, and touch Postgres.
class OrderWebhookWorker
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(webhook_event_id)
    event = WebhookEvent.find_by(id: webhook_event_id)
    return if event.nil? || event.processed?

    ActiveRecord::Base.transaction do
      event.lock!
      return if event.processed?

      OrderConfirmationService.new.confirm_order(event.payload)
      event.update!(status: :processed, processed_at: Time.current)
    end
  rescue StandardError
    event&.update(status: :failed)
    raise # let Sidekiq retry with backoff
  end
end
