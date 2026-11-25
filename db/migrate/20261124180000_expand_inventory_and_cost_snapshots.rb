class ExpandInventoryAndCostSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :cost_snapshots do |t|
      t.references :environment, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :granularity, null: false, default: "MONTHLY"
      t.string :service_code, null: false
      t.decimal :amount, precision: 12, scale: 4, null: false
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :cost_snapshots,
      %i[environment_id period_start period_end granularity service_code],
      unique: true,
      name: "index_cost_snapshots_on_environment_period_service"
  end
end
