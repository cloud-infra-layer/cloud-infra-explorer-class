require "test_helper"

class ResourceTest < ActiveSupport::TestCase
  test "persists resources and their metadata through the environment association" do
    environment = environments(:course_testing)

    %i[web_server assets_bucket].each do |fixture|
      attributes = resources(fixture).attributes.except("id", "environment_id", "created_at", "updated_at")
      resource = environment.resources.build(attributes)

      assert_difference "Resource.count", 1 do
        resource.save!
      end

      resource.reload
      assert_equal environment, resource.environment
      assert_equal attributes["metadata"], resource.metadata
      assert_includes environment.resources, resource
    end
  end

  test "requires provider, resource id, service, and name" do
    %i[provider resource_id service name].each do |attribute|
      resource = resources(:web_server).dup
      resource[attribute] = " "

      assert_not resource.valid?
      assert_includes resource.errors[attribute], "can't be blank"
    end
  end

  test "requires an environment" do
    resource = resources(:web_server).dup
    resource.environment = nil

    assert_not resource.valid?
    assert resource.errors[:environment].any?
  end

  test "rejects unsupported providers and services" do
    resource = resources(:web_server).dup
    resource.provider = "azure"
    resource.service = "lambda"

    assert_not resource.valid?
    assert_includes resource.errors[:provider], "is not included in the list"
    assert_includes resource.errors[:service], "is not included in the list"
  end

  test "requires provider to match the environment" do
    resource = resources(:web_server).dup
    resource.environment = Environment.new(name: "Other provider", provider: "azure", region: "us-east-1")

    assert_not resource.valid?
    assert_includes resource.errors[:provider], "must match the environment's provider"
  end

  test "metadata defaults to an empty hash and rejects non-object values" do
    assert_equal({}, Resource.new.metadata)

    [ nil, [], "running", 42, true ].each do |metadata|
      resource = resources(:web_server).dup
      resource.metadata = metadata

      assert_not resource.valid?
      assert_includes resource.errors[:metadata], "must be an object"
    end
  end

  test "region and console URL are optional" do
    resource = resources(:web_server).dup
    resource.region = nil
    resource.console_url = nil

    assert resource.valid?, resource.errors.full_messages.join(", ")
  end

  test "rejects duplicate EC2 identities including unknown regions" do
    original = resources(:web_server)
    assert_duplicate_identity original

    original.update!(region: nil)
    assert_duplicate_identity original
  end

  test "rejects duplicate S3 identities even when region becomes known" do
    original = resources(:assets_bucket)
    assert_duplicate_identity original
    assert_duplicate_identity original, region: "us-east-1"
  end

  test "allows the same EC2 identifier in a different region" do
    resource = resources(:web_server).dup
    resource.region = "us-west-2"

    assert resource.save, resource.errors.full_messages.join(", ")
  end

  test "allows the same identifiers in a different environment" do
    %i[web_server assets_bucket].each do |fixture|
      resource = resources(fixture).dup
      resource.environment = environments(:course_testing)

      assert resource.save, resource.errors.full_messages.join(", ")
    end
  end

  test "database rejects orphan resources and deletion of their environment" do
    environment = environments(:course_testing)
    missing_id = environment.id
    environment.destroy!

    assert_database_rejects ActiveRecord::InvalidForeignKey do
      resources(:web_server).update_columns(environment_id: missing_id)
    end

    assert_database_rejects ActiveRecord::InvalidForeignKey do
      environments(:course_development).delete
    end
  end

  test "database rejects null values for required columns" do
    %i[environment_id provider resource_id service name metadata].each do |attribute|
      assert_database_rejects ActiveRecord::NotNullViolation do
        resources(:web_server).update_columns(attribute => nil)
      end
    end
  end

  private

  def assert_duplicate_identity(original, **attributes)
    duplicate = original.dup
    duplicate.assign_attributes(attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:resource_id], "has already been taken"

    assert_database_rejects ActiveRecord::RecordNotUnique do
      duplicate.save!(validate: false)
    end
  end

  def assert_database_rejects(error, &block)
    assert_raises(error) do
      Resource.transaction(requires_new: true, &block)
    end
  end
end
