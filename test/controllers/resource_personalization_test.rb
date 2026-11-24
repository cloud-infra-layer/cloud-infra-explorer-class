require "test_helper"

class ResourcePersonalizationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original = ENV["ENABLE_RESOURCE_PERSONALIZATION"]
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    @resource = resources(:web_server)
  end

  teardown do
    @original.nil? ? ENV.delete("ENABLE_RESOURCE_PERSONALIZATION") : ENV["ENABLE_RESOURCE_PERSONALIZATION"] = @original
  end

  test "actions persist and restore preserves pinning" do
    patch pin_resource_path(@resource)
    assert_response :see_other
    assert @resource.reload.pinned?
    patch hide_resource_path(@resource)
    assert @resource.reload.hidden?
    patch restore_resource_path(@resource)
    assert_not @resource.reload.hidden?
    assert @resource.pinned?
    patch unpin_resource_path(@resource)
    assert_not @resource.reload.pinned?
    assert_redirected_to resources_path
  end

  test "each mutation rejects disabled requests" do
    %i[pin unpin hide restore].each do |action|
      path = public_send("#{action}_resource_path", @resource)
      original = @resource.reload.attributes
      ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "false"
      patch path
      assert_response :not_found
      assert_equal original, @resource.reload.attributes
      ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    end
  end

  test "action ignores attempts to update unrelated resource fields" do
    original = @resource.attributes.except("pinned", "updated_at")
    2.times do
      patch pin_resource_path(@resource), params: { resource: { name: "Injected", hidden: true, pinned: false } }
      assert @resource.reload.pinned?
      assert_equal original, @resource.attributes.except("pinned", "updated_at")
    end
  end
end
