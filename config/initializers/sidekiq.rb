Sidekiq.configure_server do |config|
  config.redis = { url: RedisConnection.url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: RedisConnection.url }
end
