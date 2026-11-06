require "test_helper"

class ResourceSyncTest < ActiveSupport::TestCase
  setup do
    @environment = environments(:course_testing)
    @sync = ResourceSync.new(environment: @environment)
  end

  test "creates both services and repeats without duplicate records or timestamp changes" do
    assert_difference "Resource.count", 2 do
      assert_equal({ created: 2, updated: 0 }, @sync.call(resources: [ ec2_record, s3_record ]))
    end
    before = @environment.resources.order(:id).map(&:attributes)

    assert_no_difference "Resource.count" do
      assert_equal({ created: 0, updated: 0 }, @sync.call(resources: [ ec2_record, s3_record ]))
    end

    assert_equal before, @environment.resources.order(:id).map(&:attributes)
    assert_equal "running", @environment.resources.find_by!(service: "ec2").metadata.fetch("state")
  end

  test "counts only changed existing records alongside newly created resources" do
    @sync.call(resources: [ ec2_record, s3_record ])
    changed = ec2_record.merge(name: "Renamed server", metadata: { instance_type: "t3.small", state: "stopped" })
    additional = s3_record.merge(resource_id: "another-example-bucket")

    assert_equal({ created: 1, updated: 1 }, @sync.call(resources: [ changed, s3_record, additional ]))

    resource = @environment.resources.find_by!(service: "ec2")
    assert_equal "Renamed server", resource.name
    assert_equal({ "instance_type" => "t3.small", "state" => "stopped" }, resource.metadata)
  end

  test "updates S3 region on the same row but keeps EC2 regions distinct" do
    @sync.call(resources: [ ec2_record, s3_record.merge(region: nil) ])
    bucket_id = @environment.resources.find_by!(service: "s3").id

    assert_equal({ created: 1, updated: 1 }, @sync.call(resources: [
      ec2_record.merge(region: "us-east-2"), s3_record
    ]))

    assert_equal bucket_id, @environment.resources.find_by!(service: "s3").id
    assert_equal "us-west-2", @environment.resources.find_by!(service: "s3").region
    assert_equal 2, @environment.resources.where(service: "ec2").count
  end

  test "accepts string keys and nullable optional fields" do
    record = ec2_record.deep_stringify_keys.except("region", "console_url")
    record["metadata"] = { "state" => nil }
    assert_equal({ created: 1, updated: 0 }, @sync.call(resources: [ record ]))
    assert_equal({ created: 0, updated: 0 }, @sync.call(resources: [ record ]))

    resource = @environment.resources.sole
    assert_nil resource.region
    assert_nil resource.console_url
  end

  test "preserves matching identities in other environments and records absent from a batch" do
    original = resources(:web_server)
    original_attributes = original.attributes
    @sync.call(resources: [ ec2_record.merge(resource_id: original.resource_id, region: original.region), s3_record ])
    bucket = @environment.resources.find_by!(service: "s3")
    bucket_attributes = bucket.attributes

    @sync.call(resources: [ ec2_record.merge(resource_id: original.resource_id, region: original.region, name: "Changed") ])

    assert_equal original_attributes, original.reload.attributes
    assert_equal bucket_attributes, bucket.reload.attributes
  end

  test "empty input preserves all inventory" do
    before = Resource.order(:id).map(&:attributes)
    assert_equal({ created: 0, updated: 0 }, @sync.call(resources: []))
    assert_equal before, Resource.order(:id).map(&:attributes)
  end

  test "rejects invalid environment and input container" do
    [ nil, Environment.new(name: "Unsaved", provider: "aws", region: "us-east-1") ].each do |environment|
      error = assert_raises(ResourceSync::Error) { ResourceSync.new(environment: environment).call(resources: []) }
      assert_equal "invalid_environment", error.code
    end

    [ nil, {}, "resources" ].each do |records|
      error = assert_raises(ResourceSync::Error) { @sync.call(resources: records) }
      assert_equal "invalid_resources", error.code
    end
  end

  test "rejects malformed records and unexpected attributes without persisting the batch" do
    malformed = [
      nil, [], ec2_record.except(:name), ec2_record.merge(resource_id: " "),
      ec2_record.merge(provider: "azure"), ec2_record.merge(service: "lambda"),
      ec2_record.merge(region: 123), ec2_record.merge(console_url: []),
      ec2_record.except(:metadata), ec2_record.merge(metadata: []),
      ec2_record.merge(metadata: { credentials: "sensitive-data" }),
      ec2_record.merge(metadata: { state: { token: "sensitive-data" } }),
      s3_record.merge(metadata: { purpose: "not in the live adapter contract" }),
      ec2_record.merge(environment_id: environments(:course_development).id),
      ec2_record.merge(id: resources(:web_server).id),
      ec2_record.merge("name" => "Conflicting key"), ec2_record.merge(123 => "invalid key")
    ]

    malformed.each do |record|
      assert_no_difference "Resource.count" do
        error = assert_raises(ResourceSync::Error) { @sync.call(resources: [ s3_record, record ]) }
        assert_equal "invalid_resource", error.code
        assert_not_includes error.message, "sensitive-data"
      end
    end
  end

  test "rejects duplicate identities including S3 records with different regions" do
    [ [ ec2_record, ec2_record.deep_stringify_keys ],
      [ s3_record, s3_record.merge(region: nil) ] ].each do |records|
      assert_no_difference "Resource.count" do
        error = assert_raises(ResourceSync::Error) { @sync.call(resources: records) }
        assert_equal "duplicate_resource", error.code
      end
    end
  end

  test "rolls back earlier inserts and updates when a later database write fails" do
    @sync.call(resources: [ ec2_record ])
    original = @environment.resources.sole
    before = original.attributes
    rejection = ->(record) do
      if record.resource_id == "reject-example-bucket"
        raise ActiveRecord::StatementInvalid, "sensitive database details"
      end
    end
    Resource.set_callback(:save, :before, rejection)

    begin
      # The caller may rescue a sync failure while still committing a Scan in
      # its own transaction. The sync's savepoint must roll back only its batch.
      Resource.transaction do
        assert_no_difference "Resource.count" do
          error = assert_raises(ResourceSync::Error) do
            @sync.call(resources: [ ec2_record.merge(name: "Changed"), s3_record,
              s3_record.merge(resource_id: "reject-example-bucket") ])
          end
          assert_equal "persistence_failed", error.code
          assert_not_includes error.message, "sensitive database details"
        end
        assert_equal before, original.reload.attributes
      end
    ensure
      Resource.skip_callback(:save, :before, rejection)
    end
  end

  private

  def ec2_record
    { provider: "aws", resource_id: "i-0123456789abcdef1", service: "ec2",
      name: "Sync server", region: "us-west-2",
      metadata: { instance_type: "t3.micro", state: "running" },
      console_url: "https://console.aws.amazon.com/ec2/" }
  end

  def s3_record
    { provider: "aws", resource_id: "sync-example-bucket", service: "s3",
      name: "sync-example-bucket", region: "us-west-2", metadata: {},
      console_url: "https://s3.console.aws.amazon.com/s3/" }
  end
end
