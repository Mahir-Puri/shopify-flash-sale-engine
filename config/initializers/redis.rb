# Single process-wide Redis client. redis-rb 5.x serializes commands with an
# internal mutex, so sharing one client across Puma/Sidekiq threads is safe.
# Every Redis touchpoint in the app goes through RedisConnection so the URL
# is configured in exactly one place.
module RedisConnection
  DEFAULT_URL = "redis://localhost:6379/0"

  def self.client
    @client ||= Redis.new(url: url)
  end

  def self.url
    ENV.fetch("REDIS_URL", DEFAULT_URL)
  end

  # Test hook: lets specs point at a scratch database and reset the memoized client.
  def self.reset!
    @client&.close
    @client = nil
  end
end
