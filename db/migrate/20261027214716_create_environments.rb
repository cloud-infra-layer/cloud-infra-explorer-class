class CreateEnvironments < ActiveRecord::Migration[8.1]
  def change
    create_table :environments do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.string :region, null: false

      t.timestamps
    end
  end
end
