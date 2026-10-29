require "test_helper"

class ResourcesControllerTest < ActionDispatch::IntegrationTest
  test "resource index and supported categories render inventory" do
    { nil => "Resources", "ec2" => "EC2 Resources", "s3" => "S3 Resources" }.each do |service, title|
      get resources_url, params: { service: service }

      assert_response :success
      assert_select "h1", title
      assert_select "h2", "Stored inventory"
      assert_select "table.resource-table", count: 1
      assert_select "a[href=?]", root_path, text: "Back to dashboard"
    end
  end

  test "unsupported service returns not found" do
    [ "lambda", "EC2", [ "ec2" ], { name: "s3" } ].each do |service|
      get resources_url, params: { service: service }
      assert_response :not_found
    end
  end

  test "each category displays only matching database records and metadata" do
    resources(:assets_bucket).update!(metadata: { purpose: "Static assets" })

    { "ec2" => :web_server, "s3" => :assets_bucket }.each do |service, fixture|
      resource = resources(fixture)
      get resources_url, params: { service: service }

      assert_response :success
      assert_select "tbody tr", count: Resource.where(provider: "aws", service: service).count
      assert_select "tbody th", resource.name
      assert_select "tbody td", resource.resource_id
      assert_select "tbody td", service.upcase
      assert_select "tbody td", resource.region.presence || "Unknown"
      assert_select "tbody td", text: service == "ec2" ? "Instance type: t3.micro · State: running" : "Purpose: Static assets"
      other = service == "ec2" ? resources(:assets_bucket) : resources(:web_server)
      assert_select "tbody th", text: other.name, count: 0
    end
  end

  test "index includes resources across environments with the dashboard AWS scope" do
    resource = resources(:web_server).dup
    resource.environment = environments(:course_testing)
    resource.name = "Another environment server"
    resource.save!

    get resources_url

    assert_response :success
    assert_select "tbody tr", count: Resource.where(provider: "aws").count
    assert_select "tbody th", resource.name
    assert_select "tbody th", resources(:assets_bucket).name
  end

  test "empty categories show helpful messages instead of a table" do
    %w[ec2 s3].each do |service|
      Resource.where(service: service).delete_all
      get resources_url, params: { service: service }

      assert_response :success
      assert_select ".empty-state", "No #{service.upcase} resources found."
      assert_select "table", count: 0
    end

    get resources_url
    assert_select ".empty-state", "No resources found."
    assert_select "table", count: 0
  end

  test "missing region and empty metadata render fallback values" do
    resources(:web_server).update!(region: nil, metadata: {})

    get resources_url, params: { service: "ec2" }

    assert_response :success
    assert_select "tbody td", "Unknown"
    assert_select "tbody td", "No metadata available"
  end

  test "resource fields and metadata are escaped" do
    html = "<script>alert('inventory')</script>"
    resources(:web_server).update!(name: html, region: html, resource_id: html, metadata: { state: html })

    get resources_url, params: { service: "ec2" }

    assert_response :success
    assert_select "tbody script", count: 0
    assert_select "tbody th", html
    assert_select "tbody td", text: html, count: 2
    assert_select "tbody td", "State: #{html}"
    assert_includes response.body, "&lt;script&gt;"
  end

  test "listing renders without AWS credential environment variables" do
    keys = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE]
    original_values = keys.to_h { |key| [ key, ENV.delete(key) ] }

    get resources_url, params: { service: "s3" }

    assert_response :success
    assert_select "tbody th", resources(:assets_bucket).name
  ensure
    original_values&.each { |key, value| ENV[key] = value }
  end
end
