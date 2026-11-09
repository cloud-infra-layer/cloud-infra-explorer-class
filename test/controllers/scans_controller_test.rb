require "test_helper"
require "base64"

class ScansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @environment = environments(:course_testing)
    @original = %w[ENABLE_MANUAL_SCANS SCAN_ADMIN_USERNAME SCAN_ADMIN_PASSWORD].to_h { |key| [ key, ENV[key] ] }
  end

  teardown do
    @original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "endpoint is unavailable without explicit enablement" do
    ENV.delete("ENABLE_MANUAL_SCANS")
    post environment_scans_path(@environment)
    assert_response :not_found
    assert_no_difference "Scan.count" do
      post environment_scans_path(@environment)
    end
  end

  test "requires credentials even when feature flag is on" do
    ENV["ENABLE_MANUAL_SCANS"] = "true"
    ENV.delete("SCAN_ADMIN_PASSWORD")
    post environment_scans_path(@environment)
    assert_response :not_found
  end

  test "rejects unauthenticated scan requests" do
    enable_scans
    assert_no_difference "Scan.count" do
      post environment_scans_path(@environment)
      assert_response :unauthorized
    end
  end

  test "rejects invalid resource types before invoking coordinator" do
    enable_scans
    post environment_scans_path(@environment), params: { resource_types: [ "lambda" ] }, headers: auth_headers
    assert_redirected_to dashboard_path
    assert_equal "Select valid EC2/S3 resource types.", flash[:alert]
  end

  test "authorized request invokes coordinator and redirects" do
    enable_scans
    fake = Object.new
    fake.define_singleton_method(:call) do |resource_types:|
      raise "Unexpected resource types" unless resource_types == %w[ec2 s3]
      Struct.new(:status, :created_count, :updated_count).new("completed", 2, 1)
    end

    ScanCoordinator.stub(:new, fake) do
      post environment_scans_path(@environment), headers: auth_headers
    end
    assert_redirected_to dashboard_path
    assert_match "2 new, 1 updated", flash[:notice]
  end

  test "scan form is hidden unless enabled" do
    get dashboard_path
    assert_select "form[action*='/scans']", count: 0

    enable_scans
    get dashboard_path
    assert_select "form[action*='/scans']", minimum: 1
  end

  private

  def enable_scans
    ENV["ENABLE_MANUAL_SCANS"] = "true"
    ENV["SCAN_ADMIN_USERNAME"] = "test-admin"
    ENV["SCAN_ADMIN_PASSWORD"] = "test-password"
  end

  def auth_headers
    { "Authorization" => "Basic #{Base64.strict_encode64('test-admin:test-password')}" }
  end
end
