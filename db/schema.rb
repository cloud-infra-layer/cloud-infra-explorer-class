# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_06_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "environments", force: :cascade do |t|
    t.string "name", null: false
    t.string "provider", null: false
    t.string "region", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "resources", force: :cascade do |t|
    t.bigint "environment_id", null: false
    t.string "provider", null: false
    t.string "resource_id", null: false
    t.string "service", null: false
    t.string "name", null: false
    t.string "region"
    t.jsonb "metadata", default: {}, null: false
    t.string "console_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id", "provider", "region", "resource_id"], name: "index_resources_on_ec2_identity", unique: true, where: "((service)::text = 'ec2'::text)", nulls_not_distinct: true
    t.index ["environment_id", "provider", "resource_id"], name: "index_resources_on_s3_identity", unique: true, where: "((service)::text = 's3'::text)"
    t.index ["environment_id"], name: "index_resources_on_environment_id"
  end

  create_table "scans", force: :cascade do |t|
    t.bigint "environment_id", null: false
    t.string "status", default: "running", null: false
    t.jsonb "resource_types", default: [], null: false
    t.integer "discovered_count", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.jsonb "error_details", default: [], null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id", "started_at"], name: "index_scans_on_environment_id_and_started_at"
    t.index ["environment_id"], name: "index_scans_on_environment_id"
    t.check_constraint "discovered_count >= 0 AND created_count >= 0 AND updated_count >= 0", name: "scans_nonnegative_counts"
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying, 'completed'::character varying, 'partial'::character varying, 'failed'::character varying]::text[])", name: "scans_valid_status"
  end

  add_foreign_key "resources", "environments"
  add_foreign_key "scans", "environments"
end
