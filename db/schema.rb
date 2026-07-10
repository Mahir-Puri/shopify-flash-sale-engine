# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.

ActiveRecord::Schema[7.1].define(version: 2026_07_01_000004) do
  enable_extension "plpgsql"

  create_table "flash_sales", force: :cascade do |t|
    t.string "shopify_product_id", null: false
    t.string "shopify_variant_id", null: false
    t.integer "inventory_count", null: false
    t.datetime "starts_at", null: false
    t.integer "reservation_timeout_seconds", default: 300, null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_variant_id"], name: "index_flash_sales_on_shopify_variant_id"
    t.index ["status"], name: "index_flash_sales_on_status"
    t.check_constraint "inventory_count >= 0", name: "inventory_count_non_negative"
    t.check_constraint "reservation_timeout_seconds > 0", name: "timeout_positive"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "flash_sale_id", null: false
    t.string "buyer_id", null: false
    t.string "reservation_token", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flash_sale_id", "buyer_id"], name: "index_reservations_on_flash_sale_id_and_buyer_id"
    t.index ["flash_sale_id"], name: "index_reservations_on_flash_sale_id"
    t.index ["reservation_token"], name: "index_reservations_on_reservation_token", unique: true
    t.index ["status"], name: "index_reservations_on_status"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.string "shopify_order_id", null: false
    t.jsonb "line_items", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["reservation_id"], name: "index_orders_on_reservation_id"
    t.index ["shopify_order_id"], name: "index_orders_on_shopify_order_id", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "shopify_order_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "received", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_order_id"], name: "index_webhook_events_on_shopify_order_id", unique: true
    t.index ["status"], name: "index_webhook_events_on_status"
  end

  add_foreign_key "orders", "reservations"
  add_foreign_key "reservations", "flash_sales"
end
