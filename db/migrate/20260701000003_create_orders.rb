class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :reservation, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.jsonb :line_items, null: false, default: []

      t.datetime :created_at, null: false
    end

    add_index :orders, :shopify_order_id, unique: true
  end
end
