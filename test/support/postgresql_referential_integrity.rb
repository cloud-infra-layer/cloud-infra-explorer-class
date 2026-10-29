# Test-only backport of Rails' PostgreSQL 18.4+ fixture compatibility fixes:
# https://github.com/rails/rails/blob/main/activerecord/lib/active_record/connection_adapters/postgresql/referential_integrity.rb
# Remove when upgrading to an ActiveRecord release containing both fixes.
require "active_record/connection_adapters/postgresql_adapter"

module PostgreSQLFixtureReferentialIntegrity
  def disable_referential_integrity(&block)
    return super unless database_version >= 180004

    with_fixture_foreign_key_enforcement(current_schemas_only: true, &block)
  end

  def check_all_foreign_keys_valid!
    return super unless database_version >= 180004

    with_fixture_foreign_key_enforcement
  end

  private
    def with_fixture_foreign_key_enforcement(current_schemas_only: false)
      # Only alter owned, enforced parent constraints. Partition copies cannot
      # be altered independently, and intentionally unenforced keys stay so.
      foreign_keys = select_all(<<~SQL).to_a
        SELECT n.nspname AS schema_name, t.relname AS table_name, c.conname AS constraint_name
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON c.connamespace = n.oid
        WHERE c.contype = 'f'
          AND c.conenforced = true
          AND c.conparentid = 0
          AND pg_catalog.pg_has_role(t.relowner, 'USAGE')
          #{"AND n.nspname = ANY (current_schemas(false))" if current_schemas_only}
      SQL

      # ENFORCED validates existing rows. Any block or validation error rolls
      # back both the data changes and the constraint changes atomically.
      transaction(requires_new: true) do
        foreign_keys.each { |key| set_fixture_foreign_key_enforcement(key, enforced: false) }
        yield if block_given?
        foreign_keys.each { |key| set_fixture_foreign_key_enforcement(key, enforced: true) }
      end
    end

    def set_fixture_foreign_key_enforcement(key, enforced:)
      table = "#{quote_column_name(key['schema_name'])}.#{quote_column_name(key['table_name'])}"
      constraint = quote_column_name(key["constraint_name"])
      execute "ALTER TABLE #{table} ALTER CONSTRAINT #{constraint} #{enforced ? 'ENFORCED' : 'NOT ENFORCED'}"
    end
end

if Rails.env.test? && ActiveRecord.version == Gem::Version.new("8.1.4")
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PostgreSQLFixtureReferentialIntegrity)
end
