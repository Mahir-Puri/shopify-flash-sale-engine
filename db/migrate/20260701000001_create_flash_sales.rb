class CreateFlashSales < ActiveRecord::Migration[7.1]
  def change
    create_table :flash_sales do |t|
      t.string :shopify_product_id, null: false
      t.string :shopify_variant_id, null: false
      t.integer :inventory_count, null: false
      t.datetime :starts_at, null: false
      t.integer :reservation_timeout_seconds, null: false, default: 300
      t.string :status, null: false, default: "scheduled"

      t.timestamps
    end

    add_index :flash_sales, :shopify_variant_id
    add_index :flash_sales, :status
    add_check_constraint :flash_sales, "inventory_count >= 0", name: "inventory_count_non_negative"
    add_check_constraint :flash_sales, "reservation_timeout_seconds > 0", name: "timeout_positive"
  end
end
