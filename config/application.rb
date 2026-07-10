require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module FlashSaleEngine
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only: no views, no asset pipeline, no cookie middleware.
    config.api_only = true

    config.active_job.queue_adapter = :sidekiq

    # Everything under app/ (services, workers) is autoloaded by Zeitwerk.
    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
