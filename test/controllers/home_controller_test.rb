require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get home_index_url
    assert_response :success
  end

  test "dashboard shows linked EC2 and S3 cards with stored counts" do
    get root_url

    assert_response :success
    assert_select ".category-card", count: 2
    assert_category_card "ec2", "EC2 Instances", Resource.where(provider: "aws", service: "ec2").count
    assert_category_card "s3", "S3 Buckets", Resource.where(provider: "aws", service: "s3").count
  end

  test "dashboard reflects changes to stored inventory" do
    resource = resources(:web_server).dup
    resource.resource_id = "i-dashboard-test"
    resource.save!

    get root_url

    assert_response :success
    assert_category_card "ec2", "EC2 Instances", Resource.where(provider: "aws", service: "ec2").count
    assert_category_card "s3", "S3 Buckets", Resource.where(provider: "aws", service: "s3").count
  end

  test "empty category stays visible and clickable alongside populated category" do
    Resource.where(service: "ec2").delete_all

    get root_url

    assert_response :success
    assert_category_card "ec2", "EC2 Instances", 0
    assert_category_card "s3", "S3 Buckets", Resource.where(provider: "aws", service: "s3").count
    assert_select ".category-card .category-description", text: "No stored resources yet.", count: 1
  end

  test "empty inventory displays both zero-count cards" do
    Resource.delete_all

    get root_url

    assert_response :success
    assert_category_card "ec2", "EC2 Instances", 0
    assert_category_card "s3", "S3 Buckets", 0
    assert_select ".category-card .category-description", text: "No stored resources yet.", count: 2
  end

  test "dashboard renders without AWS credentials" do
    credential_keys = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE]
    original_values = credential_keys.to_h { |key| [ key, ENV.delete(key) ] }

    get root_url

    assert_response :success
    assert_select ".category-card", count: 2
  ensure
    original_values&.each { |key, value| ENV[key] = value }
  end

  private
    def assert_category_card(service, name, count)
      assert_select "a.category-card[href=?]", resources_path(service: service), count: 1 do
        assert_select "h2", name
        assert_select ".resource-count", "#{count} #{count == 1 ? 'resource' : 'resources'}"
      end
    end
end
