require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "creates a demo environment with equal-weight inventory and cost snapshots" do
    assert_difference "Environment.count", 1 do
      assert_difference "Resource.count", 10 do
        assert_difference "CostSnapshot.count", 64 do
          load_seeds
        end
      end
    end

    environment = demo_environment
    assert_equal(
      { "ec2" => 3, "s3" => 3, "rds" => 2, "bedrock" => 2 },
      environment.resources.group(:service).count
    )

    environment.resources.each do |resource|
      assert resource.valid?, resource.errors.full_messages.join(", ")
      assert_equal "aws", resource.provider
      assert_equal "us-east-1", resource.region
      assert_kind_of Hash, resource.metadata
      allowed = ResourceSync::METADATA_FIELDS.fetch(resource.service)
      assert_empty(resource.metadata.keys - allowed)
    end

    instances = environment.resources.where(service: "ec2")
    assert_equal %w[running running stopped], instances.map { |resource| resource.metadata.fetch("state") }.sort
    instances.each do |resource|
      assert_match(/\Ai-[0-9a-f]{17}\z/, resource.resource_id)
      assert resource.metadata.fetch("cpu_utilization_pct").present?
      assert resource.metadata.fetch("estimated_monthly_cost_usd").present?
    end

    environment.resources.where(service: "s3").each do |resource|
      assert resource.resource_id.start_with?("course-explorer-demo-")
      assert resource.metadata.fetch("size_bytes").present?
      assert resource.metadata.fetch("object_count").present?
      assert_not resource.metadata.key?("purpose")
    end

    assert_equal 64, environment.cost_snapshots.count
    assert_equal 16, environment.cost_snapshots.distinct.pluck(:period_start).size
    assert_equal Date.new(2025, 8, 1), environment.cost_snapshots.minimum(:period_start)
    assert_equal Date.new(2026, 11, 1), environment.cost_snapshots.maximum(:period_start)
    assert environment.cost_snapshots.all? { |snapshot| snapshot.currency == "USD" }
  end

  test "rerunning seeds preserves environment and resource IDs without duplicates" do
    load_seeds
    environment_id = demo_environment.id
    resource_ids = demo_environment.resources.order(:id).pluck(:id)
    cost_ids = demo_environment.cost_snapshots.order(:id).pluck(:id)

    assert_no_difference [ "Environment.count", "Resource.count", "CostSnapshot.count" ] do
      load_seeds
    end

    assert_equal environment_id, demo_environment.id
    assert_equal resource_ids, demo_environment.resources.order(:id).pluck(:id)
    assert_equal cost_ids, demo_environment.cost_snapshots.order(:id).pluck(:id)
  end

  test "rerunning seeds refreshes demo attributes" do
    load_seeds
    resource = demo_environment.resources.find_by!(resource_id: "i-0123456789abcdef0")
    resource.update!(name: "Manually edited", metadata: { state: "stopped" }, console_url: nil)

    load_seeds

    resource.reload
    assert_equal "Demo web server", resource.name
    assert_equal "running", resource.metadata.fetch("state")
    assert_equal "t3.micro", resource.metadata.fetch("instance_type")
    assert resource.console_url.present?
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
    resource = resources(:web_server)
    environment_attributes = environment.attributes
    resource_attributes = resource.attributes

    load_seeds

    assert_equal environment_attributes, environment.reload.attributes
    assert_equal resource_attributes, resource.reload.attributes

    custom_resource = demo_environment.resources.create!(
      provider: "aws", service: "s3", resource_id: "custom-example-bucket",
      name: "Additional resource",
      metadata: { creation_date: "2026-01-01T00:00:00Z", size_bytes: "1", object_count: "1" }
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
