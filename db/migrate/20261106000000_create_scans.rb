class CreateScans < ActiveRecord::Migration[8.1]
  def change
    create_table :scans do |t|
      t.references :environment, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.jsonb :resource_types, null: false, default: []
      t.integer :discovered_count, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.jsonb :error_details, null: false, default: []
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :scans, %i[environment_id started_at]
    add_check_constraint :scans, "status IN ('running', 'completed', 'partial', 'failed')",
      name: "scans_valid_status"
    add_check_constraint :scans, "discovered_count >= 0 AND created_count >= 0 AND updated_count >= 0",
      name: "scans_nonnegative_counts"
  end
end
