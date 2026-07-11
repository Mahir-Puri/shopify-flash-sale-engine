# Verifies the X-Shopify-Hmac-SHA256 header against the raw request body.
# Two things matter here and both are easy to get wrong:
#
#   1. The digest must be computed over the RAW bytes Shopify sent, before
#      any JSON parsing. Re-serializing a parsed payload changes key order
#      and whitespace and the signature no longer matches.
#   2. The comparison must be constant-time. A plain == leaks how many
#      leading bytes matched through response timing, which is enough to
#      forge a signature byte by byte.
module WebhookVerifier
  module_function

  def valid?(raw_payload, hmac_header, secret: ENV["SHOPIFY_WEBHOOK_SECRET"])
    return false if hmac_header.blank? || secret.blank?

    digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, raw_payload)
    expected = Base64.strict_encode64(digest)
    ActiveSupport::SecurityUtils.secure_compare(expected, hmac_header)
  end
end
