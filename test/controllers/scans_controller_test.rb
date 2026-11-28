require "test_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @environment = environments(:course_testing)
    @original = ENV["ENABLE_MANUAL_SCANS"]
  end

  teardown do
    @original.nil? ? ENV.delete("ENABLE_MANUAL_SCANS") : ENV["ENABLE_MANUAL_SCANS"] = @original
  end

  test "endpoint is unavailable without explicit enablement" do
    ENV.delete("ENABLE_MANUAL_SCANS")
    post environment_scans_path(@environment)
    assert_response :not_found
    assert_no_difference "Scan.count" do
      post environment_scans_path(@environment)
    end
  end

  test "rejects invalid resource types before invoking coordinator" do
    enable_scans
    post environment_scans_path(@environment), params: { resource_types: [ "lambda" ] }
    assert_redirected_to dashboard_path(environment_id: @environment.id)
    assert_equal "Select valid inventory resource types.", flash[:alert]
  end

  test "enabled request invokes coordinator and redirects" do
    enable_scans
    fake = Object.new
    fake.define_singleton_method(:call) do |resource_types:|
      raise "Unexpected resource types" unless resource_types == Resource::SERVICES
      Struct.new(:status, :created_count, :updated_count).new("completed", 2, 1)
    end

    original_constructor = ScanCoordinator.method(:new)
    begin
      ScanCoordinator.define_singleton_method(:new) { |**_kwargs| fake }
      post environment_scans_path(@environment)
    ensure
      ScanCoordinator.define_singleton_method(:new, original_constructor)
    end
    assert_redirected_to dashboard_path(environment_id: @environment.id)
    assert_match "2 new, 1 updated", flash[:notice]
  end

  test "scan form is hidden unless enabled" do
    get dashboard_path
    assert_select "form[action*='/scans']", count: 0

    enable_scans
    get dashboard_path
    assert_select "form[action*='/scans']", minimum: 1
  end


  test "dashboard shows the latest attempt and keeps the last successful update for the selected account" do
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
      assert_select ".scan-result strong", "Partial"
      assert_select ".scan-result p", "0 created · 1 updated"
      assert_select ".scan-result li", "S3: S3 discovery unavailable."
    end
  end

  test "dashboard does not expose scan history when manual scans are disabled" do
    @environment.scans.create!(resource_types: %w[ec2], started_at: Time.current)
    ENV.delete("ENABLE_MANUAL_SCANS")
    get dashboard_path
    assert_response :success
    assert_select "form[action*='/scans']", count: 0
    assert_select ".scan-result", count: 0
  end

  test "dashboard selects the requested AWS environment and shows its empty scan history" do
    enable_scans
    other = environments(:course_development)
    other.scans.create!(resource_types: %w[ec2], started_at: Time.current)

    get dashboard_path(environment_id: @environment.id)

    assert_select "select[name=environment_id]" do
      assert_select "option[value=?][selected]", @environment.id.to_s, text: /Course testing/
      assert_select "option[value=?]:not([selected])", other.id.to_s, text: /Course development/
    end
    assert_select "form[action=?][method=post]", environment_scans_path(@environment) do
      assert_select "input[type=checkbox][name='resource_types[]'][value=ec2][checked]"
      assert_select "input[type=checkbox][name='resource_types[]'][value=s3][checked]"
    end
    assert_select ".scan-result p", "No scans recorded for this environment."
  end

  test "dashboard shows an empty environment state with no scan controls" do
    enable_scans
    Resource.delete_all
    Scan.delete_all
    Environment.delete_all

    get dashboard_path

    assert_select ".connected-account-card .empty-state", "No environments are configured."
    assert_select "form[action*='/scans']", count: 0
    assert_select ".category-grid .category-card", count: 4
  end

  test "persisted error messages are escaped" do
    enable_scans
    @environment.scans.create!(
      resource_types: %w[s3], status: "failed", started_at: 2.minutes.ago, completed_at: 1.minute.ago,
      error_details: [ { resource_type: "s3", code: "test_error", message: "<script>alert('scan')</script>" } ]
    )

    get dashboard_path(environment_id: @environment.id)

    assert_select ".scan-result strong", "Failed"
    assert_select ".scan-result li", "S3: <script>alert('scan')</script>"
    assert_select ".scan-result script", count: 0
  end

  private

  def enable_scans
    ENV["ENABLE_MANUAL_SCANS"] = "true"
  end
end
