ENV["RAILS_ENV"] ||= "test"
# Keep test Redis on its own database so a stray flushdb never touches dev data.
ENV["REDIS_URL"] ||= "redis://localhost:6379/1"
ENV["SHOPIFY_WEBHOOK_SECRET"] ||= "test_webhook_secret"

require_relative "spec_helper"
require File.expand_path("../config/environment", __dir__)

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "sidekiq/testing"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include WebhookHelpers

  # Concurrency specs open their own DB connections in threads, which cannot
  # see rows inside a wrapping transaction. Those specs opt out and clean up
  # with deletion instead.
  config.use_transactional_fixtures = true

  config.before(:each) do
    RedisConnection.client.flushdb
    Sidekiq::Worker.clear_all
  end

  config.around(:each, :no_transaction) do |example|
    self.use_transactional_tests = false
    example.run
    [Order, Reservation, WebhookEvent, FlashSale].each(&:delete_all)
  end

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
