require "test_helper"

class PostgreSQLReferentialIntegrityTest < ActiveSupport::TestCase
  setup do
    @connection = ActiveRecord::Base.connection
    skip "Requires the PostgreSQL 18.4+ backport" unless @connection.database_version >= 180004
  end

  test "invalid rows are rejected when enforcement is restored" do
    resource = resources(:web_server)
    original_environment_id = resource.environment_id

    assert_raises ActiveRecord::InvalidForeignKey do
      @connection.disable_referential_integrity do
        resource.update_columns(environment_id: -1)
      end
    end

    assert_equal original_environment_id, resource.reload.environment_id
    assert_foreign_keys_enforced
    @connection.check_all_foreign_keys_valid!
  end

  test "block exceptions roll back constraint and data changes" do
    resource = resources(:web_server)
    original_name = resource.name

    assert_raises RuntimeError do
      @connection.disable_referential_integrity do
        resource.update_columns(name: "Rolled back")
        raise "Fixture load failed"
      end
    end

    assert_equal original_name, resource.reload.name
    assert_foreign_keys_enforced
  end

  private
    def assert_foreign_keys_enforced
      assert_equal true, @connection.select_value(<<~SQL)
        SELECT bool_and(conenforced AND convalidated)
        FROM pg_constraint
        WHERE conrelid = 'resources'::regclass AND contype = 'f'
      SQL
    end
end
