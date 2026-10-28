require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "creates a demo environment with three EC2 instances and three S3 buckets" do
    assert_difference "Environment.count", 1 do
      assert_difference "Resource.count", 6 do
        load_seeds
      end
    end

    environment = demo_environment
    assert_equal({ "ec2" => 3, "s3" => 3 }, environment.resources.group(:service).count)

    environment.resources.each do |resource|
      assert resource.valid?, resource.errors.full_messages.join(", ")
      assert_equal "aws", resource.provider
      assert_equal "us-east-1", resource.region
      assert resource.name.start_with?("Demo ")
      assert_kind_of Hash, resource.metadata
    end

    instances = environment.resources.where(service: "ec2")
    assert_equal %w[running running stopped], instances.map { |resource| resource.metadata.fetch("state") }.sort
    instances.each do |resource|
      assert_match(/\Ai-[0-9a-f]{17}\z/, resource.resource_id)
      assert_includes %w[t3.micro t3.small], resource.metadata.fetch("instance_type")
      assert_equal "https://console.aws.amazon.com/ec2/", resource.console_url
    end

    environment.resources.where(service: "s3").each do |resource|
      assert resource.resource_id.start_with?("course-explorer-demo-")
      assert resource.metadata.fetch("purpose").present?
      assert_not resource.metadata.key?("state")
      assert_equal "https://s3.console.aws.amazon.com/s3/", resource.console_url
    end
  end

  test "rerunning seeds preserves environment and resource IDs without duplicates" do
    load_seeds
    environment_id = demo_environment.id
    resource_ids = demo_environment.resources.order(:id).pluck(:id)

    assert_no_difference [ "Environment.count", "Resource.count" ] do
      load_seeds
    end

    assert_equal environment_id, demo_environment.id
    assert_equal resource_ids, demo_environment.resources.order(:id).pluck(:id)
  end

  test "rerunning seeds refreshes demo attributes" do
    load_seeds
    resource = demo_environment.resources.find_by!(resource_id: "i-0123456789abcdef0")
    resource.update!(name: "Manually edited", metadata: { state: "stopped" }, console_url: nil)

    load_seeds

    resource.reload
    assert_equal "Demo web server", resource.name
    assert_equal({ "instance_type" => "t3.micro", "state" => "running" }, resource.metadata)
    assert_equal "https://console.aws.amazon.com/ec2/", resource.console_url
  end

  test "rerunning seeds updates an S3 bucket whose region was unknown" do
    load_seeds
    bucket = demo_environment.resources.find_by!(resource_id: "course-explorer-demo-assets")
    bucket.update!(region: nil)

    assert_no_difference "Resource.count" do
      load_seeds
    end

    assert_equal "us-east-1", bucket.reload.region
  end

  test "seeds preserve unrelated environments and resources including matching AWS IDs" do
    environment = environments(:course_development)
    # This fixture shares its AWS identifier with a demo instance, but belongs
    # to a different environment and must not be updated by the seed script.
    resource = resources(:web_server)
    environment_attributes = environment.attributes
    resource_attributes = resource.attributes

    load_seeds

    assert_equal environment_attributes, environment.reload.attributes
    assert_equal resource_attributes, resource.reload.attributes

    custom_resource = demo_environment.resources.create!(
      provider: "aws", service: "s3", resource_id: "custom-example-bucket",
      name: "Additional resource", metadata: { purpose: "custom" }
    )
    custom_attributes = custom_resource.attributes

    load_seeds

    assert_equal custom_attributes, custom_resource.reload.attributes
  end

  private

  def load_seeds
    load Rails.root.join("db/seeds.rb")
  end

  def demo_environment
    Environment.find_by!(name: "Course demo", provider: "aws", region: "us-east-1")
  end
end
