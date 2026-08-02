module WebhookHelpers
  # Signs a payload exactly the way Shopify does: HMAC-SHA256 over the raw
  # body, base64 encoded.
  def shopify_hmac(raw_body, secret: ENV["SHOPIFY_WEBHOOK_SECRET"])
    Base64.strict_encode64(
      OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, raw_body)
    )
  end

  def order_payload(shopify_order_id:, variant_id:, reservation_token: nil, customer_id: nil, quantity: 1)
    payload = {
      "id" => shopify_order_id,
      "line_items" => [
        { "variant_id" => variant_id, "quantity" => quantity, "title" => "Flash Sale Item" }
      ],
      "note_attributes" => []
    }
    payload["note_attributes"] << { "name" => "reservation_token", "value" => reservation_token } if reservation_token
    payload["customer"] = { "id" => customer_id } if customer_id
    payload
  end

  def post_signed_webhook(path, payload)
    raw = payload.to_json
    post path, params: raw, headers: {
      "CONTENT_TYPE" => "application/json",
      "X-Shopify-Hmac-SHA256" => shopify_hmac(raw)
    }
  end
end
