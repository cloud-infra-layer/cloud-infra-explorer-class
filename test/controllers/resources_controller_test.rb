require "test_helper"

class ResourcesControllerTest < ActionDispatch::IntegrationTest
  test "resource index and supported categories render placeholders" do
    { nil => "Resources", "ec2" => "EC2 Resources", "s3" => "S3 Resources" }.each do |service, title|
      get resources_url, params: { service: service }

      assert_response :success
      assert_select "h1", title
      assert_select "h2", "Resource listing coming soon"
      assert_select "a[href=?]", root_path, text: "Back to dashboard"
    end
  end

  test "unsupported service returns not found" do
    get resources_url, params: { service: "lambda" }
    assert_response :not_found
  end
end
