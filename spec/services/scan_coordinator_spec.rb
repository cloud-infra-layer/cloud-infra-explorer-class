require "rails_helper"

RSpec.describe ScanCoordinator do
  let(:environment) { Environment.create!(name: "Coordinator specs", provider: "aws", region: "us-east-2") }
  let(:ec2) do
    { provider: "aws", service: "ec2", resource_id: "i-coordinator", name: "Server", region: environment.region,
      metadata: { instance_type: "t3.micro", state: "running" }, console_url: nil }
  end
  let(:s3) do
    { provider: "aws", service: "s3", resource_id: "coordinator-bucket", name: "Bucket", region: environment.region,
      metadata: {}, console_url: nil }
  end
  let(:result) { { resources: [ ec2, s3 ], errors: [] } }
  let(:adapter) { instance_double(CloudProvider::Adapter, list_resources: result) }
  subject(:coordinator) { described_class.new(environment: environment, adapter: adapter) }

  def error_for(service)
    { resource_type: service, code: "aws_api_error", message: "Discovery unavailable." }
  end

  def personalized_inventory
    [ ec2, s3 ].map { |attributes| environment.resources.create!(attributes.merge(pinned: true, hidden: true)) }
  end

  def snapshot
    environment.resources.order(:id).map(&:attributes)
  end

  it "persists a running scan before discovery and finishes with stored inventory and counts" do
    expect(adapter).to receive(:list_resources).with(provider: "aws", region: environment.region, resource_types: %w[ec2 s3]) do
      running = environment.scans.sole
      expect(running).to have_attributes(status: "running", completed_at: nil)
      expect(running.started_at).not_to be_nil
      result
    end
    scan = nil
    expect { scan = coordinator.call(resource_types: %w[ec2 s3]) }.to change { environment.scans.count }.by(1)
      .and change { environment.resources.count }.by(2)

    expect(scan.reload).to have_attributes(status: "completed", resource_types: %w[ec2 s3],
      discovered_count: 2, created_count: 2, updated_count: 0, error_details: [])
    expect(scan.completed_at).to be >= scan.started_at
    expect(environment.resources.find_by!(service: "ec2").metadata).to eq("instance_type" => "t3.micro", "state" => "running")
  end

  it "records valid empty discovery as completed without deleting existing inventory" do
    personalized_inventory
    original = snapshot
    allow(adapter).to receive(:list_resources).and_return(resources: [], errors: [])
    scan = coordinator.call(resource_types: %w[ec2 s3]).reload
    expect(scan).to have_attributes(status: "completed", discovered_count: 0, created_count: 0, updated_count: 0)
    expect(snapshot).to eq(original)
  end

  it "refreshes both services in place while preserving personalization, then reports an unchanged repeat" do
    resources = personalized_inventory
    ids = resources.map(&:id)
    changed = [ ec2.merge(name: "Updated server", metadata: { state: "stopped" }), s3.merge(name: "Updated bucket") ]
    allow(adapter).to receive(:list_resources).and_return(resources: changed, errors: [])

    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "completed", created_count: 0, updated_count: 2)
    expect(environment.resources.order(:id).pluck(:id)).to eq(ids)
    expect(resources.map { |resource| resource.reload.name }).to eq([ "Updated server", "Updated bucket" ])
    expect(resources.map { |resource| [ resource.pinned, resource.hidden ] }).to eq([ [ true, true ], [ true, true ] ])
    original = snapshot
    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "completed", created_count: 0, updated_count: 0)
    expect(snapshot).to eq(original)
  end

  %w[ec2 s3].each do |failed_service|
    it "updates the successful personalized service while preserving failed #{failed_service} inventory" do
      personalized_inventory
      failed = environment.resources.find_by!(service: failed_service)
      original = failed.attributes
      successful = environment.resources.where.not(service: failed_service).sole
      error = error_for(failed_service)
      allow(adapter).to receive(:list_resources).and_return(
        resources: [ ec2.merge(name: "Updated ec2"), s3.merge(name: "Updated s3") ], errors: [ error ])

      scan = coordinator.call(resource_types: %w[ec2 s3]).reload
      expect(scan).to have_attributes(status: "partial", discovered_count: 1, created_count: 0, updated_count: 1,
        error_details: [ error.stringify_keys ])
      expect(failed.reload.attributes).to eq(original)
      expect(successful.reload).to have_attributes(name: "Updated #{successful.service}", pinned: true, hidden: true)
      expect(environment.resources.count).to eq(2)
    end
  end

  it "inserts successful discoveries in a partial scan and ignores failed-service payloads" do
    previous = environment.resources.create!(ec2.merge(resource_id: "i-previous"))
    allow(adapter).to receive(:list_resources).and_return(resources: [ ec2, s3 ], errors: [ error_for("ec2") ])
    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "partial", discovered_count: 1, created_count: 1, updated_count: 0)
    expect(previous.reload).to be_persisted
    expect(environment.resources.exists?(resource_id: ec2[:resource_id])).to be(false)
    expect(environment.resources.exists?(resource_id: s3[:resource_id])).to be(true)
  end

  it "distinguishes partial empty results from complete discovery failure" do
    personalized_inventory
    original = snapshot
    allow(adapter).to receive(:list_resources).and_return(resources: [], errors: [ error_for("ec2") ])
    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "partial", discovered_count: 0, created_count: 0, updated_count: 0)
    allow(adapter).to receive(:list_resources).and_return(resources: [], errors: [ error_for("ec2"), error_for("s3") ])
    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "failed", discovered_count: 0, created_count: 0, updated_count: 0)
    expect(snapshot).to eq(original)
  end

  it "rejects all discovery results after a connection-wide failure" do
    personalized_inventory
    original = snapshot
    allow(adapter).to receive(:list_resources).and_return(resources: [ ec2.merge(name: "Must not save") ], errors: [ error_for("connection") ])
    expect(coordinator.call(resource_types: %w[ec2 s3]).reload).to have_attributes(status: "failed", discovered_count: 0, updated_count: 0)
    expect(snapshot).to eq(original)
  end

  it "records a safe persistence failure without claiming successful writes" do
    personalized_inventory
    original = snapshot
    sync = instance_double(ResourceSync)
    expect(sync).to receive(:call).with(resources: [ ec2, s3 ]).and_raise(ResourceSync::Error.new("persistence_failed", "Synchronization failed."))
    failing = described_class.new(environment: environment, adapter: adapter,
      sync_factory: ->(selected) { expect(selected).to eq(environment); sync })

    scan = failing.call.reload
    expect(scan).to have_attributes(status: "failed", discovered_count: 0, created_count: 0, updated_count: 0,
      error_details: [ { "resource_type" => "persistence", "code" => "persistence_failed", "message" => "Synchronization failed." } ])
    expect(scan.completed_at).not_to be_nil
    expect(snapshot).to eq(original)
  end

  it "persists failure and retains inventory when the real sync rejects a batch" do
    personalized_inventory
    original = snapshot
    allow(adapter).to receive(:list_resources).and_return(resources: [ ec2.merge(name: "Must not save"), s3.merge(pinned: false) ], errors: [])
    scan = coordinator.call(resource_types: %w[ec2 s3]).reload
    expect(scan).to have_attributes(status: "failed", created_count: 0, updated_count: 0)
    expect(scan.error_details.first).to include("resource_type" => "persistence", "code" => "invalid_resource")
    expect(snapshot).to eq(original)
  end

  it "sanitizes unexpected discovery exceptions" do
    allow(adapter).to receive(:list_resources).and_raise(StandardError, "private-sdk-value")
    scan = coordinator.call(resource_types: %w[ec2 s3]).reload
    expect(scan).to have_attributes(status: "failed", created_count: 0, updated_count: 0)
    expect(scan.error_details.first).to include("code" => "discovery_failed")
    expect(scan.error_details.to_s).not_to include("private-sdk-value")
    expect(environment.resources).to be_empty
  end

  [ nil, { resources: "bad", errors: [] }, { resources: [], errors: "bad" },
    { resources: [], errors: [ { code: "missing-fields" } ] },
    { resources: [ { service: "lambda" } ], errors: [] } ].each do |malformed|
    it "records safe failure for malformed adapter result #{malformed.inspect}" do
      allow(adapter).to receive(:list_resources).and_return(malformed)
      scan = coordinator.call(resource_types: %w[ec2 s3]).reload
      expect(scan.status).to eq("failed")
      expect(scan.error_details.first).to include("code" => "discovery_failed")
      expect(environment.resources).to be_empty
    end
  end

  [ [], [ "ec2", "ec2" ], [ "lambda" ], nil ].each do |types|
    it "rejects invalid types #{types.inspect} before discovery or scan creation" do
      expect(adapter).not_to receive(:list_resources)
      expect { coordinator.call(resource_types: types) }.to raise_error(ArgumentError)
      expect(environment.scans).to be_empty
    end
  end

  it "rejects missing and unpersisted environments before discovery" do
    expect(adapter).not_to receive(:list_resources)
    [ nil, Environment.new(name: "Unsaved", provider: "aws", region: "us-east-2") ].each do |invalid|
      expect { described_class.new(environment: invalid, adapter: adapter).call }.to raise_error(ArgumentError)
    end
  end

  it "supports string-keyed results and single-service requests" do
    expect(adapter).to receive(:list_resources).with(provider: "aws", region: environment.region, resource_types: [ "s3" ])
      .and_return("resources" => [ s3.stringify_keys ], "errors" => [])
    expect(coordinator.call(resource_types: [ "s3" ]).reload).to have_attributes(status: "completed", created_count: 1)
    expect(environment.resources.pluck(:service)).to eq([ "s3" ])
  end
end
