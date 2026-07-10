class CreateReservations < ActiveRecord::Migration[7.1]
  def change
    create_table :reservations do |t|
      t.references :flash_sale, null: false, foreign_key: true
      t.string :buyer_id, null: false
      t.string :reservation_token, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false

      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :reservations, :reservation_token, unique: true
    add_index :reservations, [:flash_sale_id, :buyer_id]
    add_index :reservations, :status
  end
end
