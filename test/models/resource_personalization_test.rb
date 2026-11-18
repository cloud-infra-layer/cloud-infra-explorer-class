require "test_helper"

class ResourcePersonalizationTest < ActiveSupport::TestCase
  test "personalization defaults to visible and unpinned" do
    resource = Resource.new
    assert_equal false, resource.pinned
    assert_equal false, resource.hidden
    assert_equal false, resources(:web_server).reload.pinned
    assert_equal false, resources(:web_server).hidden
  end

  test "restoring preserves the pin and unpinning persists" do
    resource = resources(:web_server)
    resource.update!(pinned: true, hidden: true)
    assert resource.reload.pinned?
    assert resource.hidden?
    resource.update!(hidden: false)
    assert_not resource.reload.hidden?
    assert resource.pinned?
    resource.update!(pinned: false)
    assert_not resource.reload.pinned?
  end

  test "visible and hidden scopes preserve inventory and support pinned ordering" do
    web = resources(:web_server)
    bucket = resources(:assets_bucket)
    web.update!(name: "A server")
    bucket.update!(name: "Z bucket", pinned: true)
    inventory = Resource.where(id: [ web.id, bucket.id ])

    assert_equal [ bucket.id, web.id ], inventory.visible.pinned_first.pluck(:id)
    bucket.update!(hidden: true)
    assert_equal [ web.id ], inventory.visible.pluck(:id)
    assert_equal [ bucket.id ], inventory.hidden.pluck(:id)
    assert_equal 2, inventory.count
  end

  test "null personalization is rejected by validation and the database" do
    %i[pinned hidden].each do |attribute|
      resource = resources(:web_server).reload
      resource[attribute] = nil
      assert_not resource.valid?
      assert resource.errors[attribute].any?
      assert_raises ActiveRecord::NotNullViolation do
        Resource.transaction(requires_new: true) { resource.update_columns(attribute => nil) }
      end
    end
  end
end
