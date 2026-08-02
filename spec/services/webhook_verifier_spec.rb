require "rails_helper"

RSpec.describe WebhookVerifier do
  let(:secret) { "test_webhook_secret" }
  let(:payload) { { id: 123, total: "9.99" }.to_json }
  let(:valid_hmac) do
    Base64.strict_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, payload))
  end

  it "accepts a correctly signed payload" do
    expect(described_class.valid?(payload, valid_hmac, secret: secret)).to be(true)
  end

  it "rejects a tampered payload" do
    tampered = payload.sub("9.99", "0.01")
    expect(described_class.valid?(tampered, valid_hmac, secret: secret)).to be(false)
  end

  it "rejects a missing header" do
    expect(described_class.valid?(payload, nil, secret: secret)).to be(false)
  end

  it "rejects a signature made with the wrong secret" do
    wrong = Base64.strict_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), "other", payload))
    expect(described_class.valid?(payload, wrong, secret: secret)).to be(false)
  end
end
