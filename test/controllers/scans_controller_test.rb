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

    original_constructor = ScanCoordinator.method(:new)
    begin
      ScanCoordinator.define_singleton_method(:new) { |**_kwargs| fake }
      post environment_scans_path(@environment), headers: auth_headers
    ensure
      ScanCoordinator.define_singleton_method(:new, original_constructor)
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


  test "dashboard shows one refresh form and last completed scan for selected account" do
    enable_scans
    selected = Environment.find_or_create_by!(
      name: "AWS Sandbox", provider: "aws", region: "us-east-2"
    )
    completed_at = 1.hour.ago.change(sec: 0)
    completed = selected.scans.create!(
      resource_types: %w[ec2],
      started_at: completed_at - 5.minutes
    )
    completed.update!(
      status: "completed", completed_at: completed_at,
      discovered_count: 1, created_count: 1, updated_count: 0
    )

    partial = selected.scans.create!(
      resource_types: %w[ec2 s3], started_at: 30.minutes.ago
    )
    partial.update!(
      status: "partial", completed_at: 20.minutes.ago,
      discovered_count: 2, created_count: 0, updated_count: 1,
      error_details: [ {
        "resource_type" => "s3", "code" => "aws_api_error",
        "message" => "S3 discovery unavailable."
      } ]
    )

    get dashboard_path
    assert_response :success
    assert_select ".connected-account-card", count: 1 do
      assert_select "h2", text: "AWS Sandbox"
      assert_select "form[action=?]", environment_scans_path(selected), count: 1
      assert_select "time[datetime]", count: 1 do |nodes|
        assert_equal completed_at.to_i, Time.iso8601(nodes.first["datetime"]).to_i
      end
      assert_select "p[role=status]", count: 0
    end
    assert_select "li", text: /S3 discovery unavailable/, count: 0
  end

  test "dashboard does not expose scan history when manual scans are disabled" do
    @environment.scans.create!(resource_types: %w[ec2], started_at: Time.current)
    ENV.delete("ENABLE_MANUAL_SCANS")
    get dashboard_path
    assert_response :success
    assert_select "form[action*='/scans']", count: 0
    assert_select "p[role=status]", text: /Latest scan:/, count: 0
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
