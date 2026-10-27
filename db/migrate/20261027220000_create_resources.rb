class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.references :environment, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :resource_id, null: false
      t.string :service, null: false
      t.string :name, null: false
      t.string :region
      t.jsonb :metadata, null: false, default: {}
      t.string :console_url

      t.timestamps
    end

    add_index :resources, %i[environment_id provider region resource_id],
      unique: true, where: "service = 'ec2'", nulls_not_distinct: true,
      name: "index_resources_on_ec2_identity"

    add_index :resources, %i[environment_id provider resource_id],
      unique: true, where: "service = 's3'",
      name: "index_resources_on_s3_identity"
  end
end
