require "test_helper"

class ResourcePersonalizationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original = %w[ENABLE_RESOURCE_PERSONALIZATION RESOURCE_ADMIN_USERNAME RESOURCE_ADMIN_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    ENV["RESOURCE_ADMIN_USERNAME"] = "test-editor"
    ENV["RESOURCE_ADMIN_PASSWORD"] = "test-password"
    @resource = resources(:web_server)
    @headers = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("test-editor", "test-password") }
  end

  teardown do
    @original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "authorized actions persist and restore preserves pinning" do
    patch pin_resource_path(@resource), headers: @headers
    assert_response :see_other
    assert @resource.reload.pinned?
    patch hide_resource_path(@resource), headers: @headers
    assert @resource.reload.hidden?
    patch restore_resource_path(@resource), headers: @headers
    assert_not @resource.reload.hidden?
    assert @resource.pinned?
    patch unpin_resource_path(@resource), headers: @headers
    assert_not @resource.reload.pinned?
    assert_redirected_to resources_path
  end

  test "each mutation rejects unauthenticated and disabled requests" do
    %i[pin unpin hide restore].each do |action|
      path = public_send("#{action}_resource_path", @resource)
      original = @resource.reload.attributes
      patch path
      assert_response :unauthorized
      ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "false"
      patch path, headers: @headers
      assert_response :not_found
      assert_equal original, @resource.reload.attributes
      ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    end
  end

  test "action ignores attempts to update unrelated resource fields" do
    original = @resource.attributes.except("pinned", "updated_at")
    2.times do
      patch pin_resource_path(@resource), headers: @headers, params: { resource: { name: "Injected", hidden: true, pinned: false } }
      assert @resource.reload.pinned?
      assert_equal original, @resource.attributes.except("pinned", "updated_at")
    end
  end
end
