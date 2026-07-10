class CreateWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_events do |t|
      t.string :shopify_order_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.datetime :processed_at

      t.timestamps
    end

    # The idempotency backbone: a duplicate delivery can never create a second
    # row, no matter how the requests interleave.
    add_index :webhook_events, :shopify_order_id, unique: true
    add_index :webhook_events, :status
  end
end
