require "test_helper"

class ScanCoordinatorTest < ActiveSupport::TestCase
  class FakeAdapter
    attr_reader :received_context

    def initialize(result)
      @result = result
    end

    def list_resources(connection_context)
      @received_context = connection_context
      @result
    end
  end

  setup do
    @environment = environments(:course_testing)
  end

  test "persists discovered resources and records a completed scan" do
    adapter = FakeAdapter.new(resources: [ ec2_record, s3_record ], errors: [])

    assert_difference -> { @environment.resources.count } => 2, -> { Scan.count } => 1 do
      @scan = ScanCoordinator.new(environment: @environment, adapter: adapter).call(resource_types: %w[ec2 s3])
    end

    assert_equal "completed", @scan.status
    assert_equal [ "ec2", "s3" ], @scan.resource_types
    assert_equal({ provider: "aws", region: @environment.region, resource_types: [ "ec2", "s3" ] },
      adapter.received_context)
    assert_equal 2, @scan.discovered_count
    assert_equal 2, @scan.created_count
    assert_equal 0, @scan.updated_count
    assert_empty @scan.error_details
    assert_not_nil @scan.completed_at
  end

  test "repeat scan updates changed resources without duplicating records" do
    original = FakeAdapter.new(resources: [ ec2_record ], errors: [])
    ScanCoordinator.new(environment: @environment, adapter: original).call(resource_types: [ "ec2" ])
    changed = ec2_record.merge(name: "Renamed instance")

    assert_no_difference -> { @environment.resources.count } do
      scan = ScanCoordinator.new(environment: @environment,
        adapter: FakeAdapter.new(resources: [ changed ], errors: [])).call(resource_types: [ "ec2" ])
      assert_equal "completed", scan.status
      assert_equal 0, scan.created_count
      assert_equal 1, scan.updated_count
    end
    assert_equal "Renamed instance", @environment.resources.find_by!(service: "ec2").name
  end

  test "partial AWS failure saves only successful service and preserves inventory" do
    old = @environment.resources.create!(ec2_record.merge(resource_id: "i-previous"))
    error = { resource_type: "ec2", code: "aws_api_error", message: "EC2 unavailable." }
    adapter = FakeAdapter.new(resources: [ ec2_record, s3_record ], errors: [ error ])
    scan = ScanCoordinator.new(environment: @environment, adapter: adapter).call(resource_types: %w[ec2 s3])

    assert_equal "partial", scan.status
    assert_equal 1, scan.discovered_count
    assert_equal 1, scan.created_count
    assert_equal [ error.stringify_keys ], scan.error_details
    assert old.reload.persisted?
    assert_not @environment.resources.exists?(resource_id: ec2_record[:resource_id])
    assert @environment.resources.exists?(resource_id: s3_record[:resource_id])
  end

  test "all failed discovery preserves existing inventory" do
    old = @environment.resources.create!(ec2_record)
    adapter = FakeAdapter.new(resources: [], errors: [
      { resource_type: "ec2", code: "credentials_unavailable", message: "No credentials." }
    ])
    scan = ScanCoordinator.new(environment: @environment, adapter: adapter).call(resource_types: [ "ec2" ])

    assert_equal "failed", scan.status
    assert_equal 0, scan.created_count
    assert_equal 0, scan.updated_count
    assert old.reload.persisted?
  end

  test "connection failure does not persist any resources" do
    adapter = FakeAdapter.new(resources: [ ec2_record ], errors: [
      { resource_type: "connection", code: "invalid_context", message: "Invalid context." }
    ])
    assert_no_difference "Resource.count" do
      scan = ScanCoordinator.new(environment: @environment, adapter: adapter).call(resource_types: %w[ec2 s3])
      assert_equal "failed", scan.status
    end
  end

  test "malformed adapter response records safe failure and does not write" do
    adapter = FakeAdapter.new(resources: "bad response", errors: [])
    assert_no_difference "Resource.count" do
      scan = ScanCoordinator.new(environment: @environment, adapter: adapter).call(resource_types: %w[ec2 s3])
      assert_equal "failed", scan.status
      assert_equal "discovery_failed", scan.error_details.first.fetch("code")
    end
  end

  test "rejects invalid requested types before creating a scan" do
    [ [], [ "ec2", "ec2" ], [ "lambda" ], nil ].each do |types|
      assert_no_difference "Scan.count" do
        assert_raises(ArgumentError) do
          ScanCoordinator.new(environment: @environment, adapter: FakeAdapter.new({})).call(resource_types: types)
        end
      end
    end
  end

  test "persistence failure records a failed scan and preserves inventory" do
    existing = @environment.resources.create!(ec2_record)

    failing_sync = ->(_environment) {
      Object.new.tap do |sync|
        sync.define_singleton_method(:call) do |resources:|
          raise ResourceSync::Error.new(
            "persistence_failed",
            "Resource synchronization failed."
          )
        end
      end
    }

    adapter = FakeAdapter.new(
      resources: [ s3_record ],
      errors: []
    )

    assert_no_difference "Resource.count" do
      scan = ScanCoordinator.new(
        environment: @environment,
        adapter: adapter,
        sync_factory: failing_sync
      ).call(resource_types: %w[ec2 s3])

      assert_equal "failed", scan.status
      assert_equal 0, scan.discovered_count
      assert_equal 0, scan.created_count
      assert_equal 0, scan.updated_count
      assert_equal "persistence_failed",
        scan.error_details.first.fetch("code")
      assert_not_nil scan.completed_at
    end

    assert existing.reload.persisted?
  end

  test "successful refresh preserves personalization and database identity" do
    ScanCoordinator.new(environment: @environment,
      adapter: FakeAdapter.new(resources: [ ec2_record, s3_record ], errors: [])).call(resource_types: %w[ec2 s3])
    @environment.resources.each { |resource| resource.update!(pinned: true, hidden: true) }
    original_ids = @environment.resources.order(:id).pluck(:id)
    refreshed = [
      ec2_record.merge(name: "Refreshed EC2", metadata: { instance_type: "t3.small", state: "stopped" }),
      s3_record.merge(name: "Refreshed bucket")
    ]

    scan = ScanCoordinator.new(environment: @environment,
      adapter: FakeAdapter.new(resources: refreshed, errors: [])).call(resource_types: %w[ec2 s3])

    assert_equal "completed", scan.status
    assert_equal 0, scan.created_count
    assert_equal 2, scan.updated_count
    assert_equal original_ids, @environment.resources.order(:id).pluck(:id)
    assert_equal [ [ true, true ], [ true, true ] ], @environment.resources.order(:id).pluck(:pinned, :hidden)
    assert_equal "Refreshed EC2", @environment.resources.find_by!(service: "ec2").name
    assert_equal({ "instance_type" => "t3.small", "state" => "stopped" },
      @environment.resources.find_by!(service: "ec2").metadata)
  end

  test "partial and failed scans leave personalized inventory untouched" do
    ScanCoordinator.new(environment: @environment,
      adapter: FakeAdapter.new(resources: [ ec2_record, s3_record ], errors: [])).call(resource_types: %w[ec2 s3])
    @environment.resources.each { |resource| resource.update!(pinned: true, hidden: true) }
    snapshot = @environment.resources.order(:id).map(&:attributes)

    partial = ScanCoordinator.new(environment: @environment, adapter: FakeAdapter.new(
      resources: [ ec2_record.merge(name: "Must not apply"), s3_record ],
      errors: [ { resource_type: "ec2", code: "aws_api_error", message: "EC2 unavailable." } ]
    )).call(resource_types: %w[ec2 s3])
    assert_equal "partial", partial.status
    assert_equal 0, partial.created_count
    assert_equal 0, partial.updated_count
    assert_equal snapshot, @environment.resources.order(:id).map(&:attributes)

    failed = ScanCoordinator.new(environment: @environment, adapter: FakeAdapter.new(
      resources: [],
      errors: [
        { resource_type: "ec2", code: "credentials_unavailable", message: "No credentials." },
        { resource_type: "s3", code: "credentials_unavailable", message: "No credentials." }
      ]
    )).call(resource_types: %w[ec2 s3])
    assert_equal "failed", failed.status
    assert_equal snapshot, @environment.resources.order(:id).map(&:attributes)
  end

  private

  def ec2_record
    { provider: "aws", resource_id: "i-scan-integration", service: "ec2",
      name: "Test EC2", region: @environment.region,
      metadata: { instance_type: "t3.micro", state: "running" }, console_url: nil }
  end

  def s3_record
    { provider: "aws", resource_id: "scan-integration-bucket", service: "s3",
      name: "scan-integration-bucket", region: @environment.region,
      metadata: {}, console_url: nil }
  end
end
