require "rails_helper"

RSpec.describe ResourceSync do
  let(:environment) do
    Environment.create!(name: "Sync specs", provider: "aws", region: "us-west-2")
  end
  let(:sync) { described_class.new(environment: environment) }
  let(:ec2_record) do
    { provider: "aws", resource_id: "i-0123456789abcdef1", service: "ec2",
      name: "Example server", region: "us-west-2",
      metadata: { instance_type: "t3.micro", state: "running" },
      console_url: "https://console.aws.amazon.com/ec2/" }
  end
  let(:s3_record) do
    { provider: "aws", resource_id: "rspec-example-bucket", service: "s3",
      name: "Example bucket", region: "us-west-2", metadata: {},
      console_url: "https://s3.console.aws.amazon.com/s3/" }
  end

  describe "#call" do
    context "when discovering new inventory" do
      it "creates both services within the selected environment and reports accurate counts" do
        result = nil
        expect { result = sync.call(resources: [ ec2_record, s3_record ]) }.to change(Resource, :count).by(2)

        expect(result).to eq(created: 2, updated: 0)
        expect(environment.resources.pluck(:service)).to match_array(%w[ec2 s3])
        instance = environment.resources.find_by!(service: "ec2")
        expect(instance).to have_attributes(name: "Example server", region: "us-west-2")
        expect(instance.metadata).to eq("instance_type" => "t3.micro", "state" => "running")
      end

      it "accepts string keys and null optional fields" do
        record = ec2_record.deep_stringify_keys.except("region", "console_url")
        record["metadata"] = { "state" => nil }

        expect(sync.call(resources: [ record ])).to eq(created: 1, updated: 0)
        expect(sync.call(resources: [ record ])).to eq(created: 0, updated: 0)
        expect(environment.resources.sole).to have_attributes(region: nil, console_url: nil, metadata: { "state" => nil })
      end

      it "does not mutate caller-owned hashes or nested metadata" do
        records = [ ec2_record, s3_record.deep_stringify_keys ]
        original = records.deep_dup
        records.each do |record|
          (record[:metadata] || record["metadata"]).freeze
          record.freeze
        end
        records.freeze

        expect(sync.call(resources: records)).to eq(created: 2, updated: 0)
        expect(records).to eq(original)
      end
    end

    context "when inventory already exists" do
      before { sync.call(resources: [ ec2_record, s3_record ]) }

      it "preserves IDs, attributes, and timestamps on an unchanged repeat" do
        original = inventory_snapshot

        expect(sync.call(resources: [ ec2_record, s3_record ])).to eq(created: 0, updated: 0)

        expect(inventory_snapshot).to eq(original)
      end

      it "counts inserts and changed rows separately while leaving unchanged rows alone" do
        instance = environment.resources.find_by!(service: "ec2")
        original_bucket = environment.resources.find_by!(service: "s3").attributes
        changed = ec2_record.merge(name: "Renamed server", metadata: { instance_type: "t3.small", state: "stopped" })
        additional = s3_record.merge(resource_id: "another-rspec-bucket")

        expect(sync.call(resources: [ changed, s3_record, additional ])).to eq(created: 1, updated: 1)

        expect(instance.reload).to have_attributes(name: "Renamed server", metadata: { "instance_type" => "t3.small", "state" => "stopped" })
        expect(Resource.find(original_bucket.fetch("id")).attributes).to eq(original_bucket)
        expect(environment.resources.count).to eq(3)
      end

      it "preserves resources omitted from a later discovery result" do
        original_bucket = environment.resources.find_by!(service: "s3").attributes

        expect(sync.call(resources: [ ec2_record.merge(name: "Changed") ])).to eq(created: 0, updated: 1)

        expect(Resource.find(original_bucket.fetch("id")).attributes).to eq(original_bucket)
      end

      it "treats empty input as a successful no-op" do
        original = inventory_snapshot

        expect(sync.call(resources: [])).to eq(created: 0, updated: 0)

        expect(inventory_snapshot).to eq(original)
      end

      it "clears an omitted console URL without changing EC2 identity" do
        instance = environment.resources.find_by!(service: "ec2")

        expect(sync.call(resources: [ ec2_record.except(:console_url) ])).to eq(created: 0, updated: 1)

        expect(instance.reload.console_url).to be_nil
        expect(environment.resources.where(service: "ec2").count).to eq(1)
      end

      it "clears omitted S3 region and console URL on the existing bucket" do
        bucket = environment.resources.find_by!(service: "s3")

        expect(sync.call(resources: [ s3_record.except(:region, :console_url) ])).to eq(created: 0, updated: 1)

        expect(bucket.reload).to have_attributes(region: nil, console_url: nil)
        expect(environment.resources.where(service: "s3").count).to eq(1)
      end
    end

    describe "resource identity" do
      it "keeps EC2 instances with the same identifier in different regions separate" do
        records = [ ec2_record, ec2_record.merge(region: "us-east-2") ]

        expect(sync.call(resources: records)).to eq(created: 2, updated: 0)
        expect(environment.resources.pluck(:region)).to match_array(%w[us-west-2 us-east-2])
      end

      it "updates an S3 bucket whose region becomes known instead of inserting another row" do
        sync.call(resources: [ s3_record.merge(region: nil) ])
        bucket = environment.resources.sole

        expect(sync.call(resources: [ s3_record ])).to eq(created: 0, updated: 1)

        expect(bucket.reload.region).to eq("us-west-2")
        expect(environment.resources.pluck(:id)).to eq([ bucket.id ])
      end

      it "preserves identical AWS identities belonging to another environment" do
        other = Environment.create!(name: "Other specs", provider: "aws", region: "us-west-2")
        described_class.new(environment: other).call(resources: [ ec2_record, s3_record ])
        original = other.resources.order(:id).map(&:attributes)

        expect(sync.call(resources: [ ec2_record, s3_record ])).to eq(created: 2, updated: 0)
        sync.call(resources: [ ec2_record.merge(name: "Changed only here") ])

        expect(other.resources.order(:id).map(&:attributes)).to eq(original)
      end

      {
        "EC2 symbol and string keys" => ->(ec2, _) { [ ec2, ec2.deep_stringify_keys ] },
        "EC2 unknown regions" => ->(ec2, _) { [ ec2.merge(region: nil), ec2.except(:region) ] },
        "S3 differing regions" => ->(_, s3) { [ s3, s3.merge(region: nil) ] }
      }.each do |description, records_for|
        it "rejects duplicate identities for #{description} without writes" do
          original = inventory_snapshot
          expect do
            sync.call(resources: records_for.call(ec2_record, s3_record))
          end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("duplicate_resource") }
          expect(inventory_snapshot).to eq(original)
        end
      end
    end

    describe "invalid input" do
      it "rejects a missing environment" do
        expect do
          described_class.new(environment: nil).call(resources: [])
        end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_environment") }
      end

      it "rejects an unsaved environment" do
        unsaved = Environment.new(name: "Unsaved", provider: "aws", region: "us-west-2")
        expect do
          described_class.new(environment: unsaved).call(resources: [])
        end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_environment") }
      end

      it "rejects an environment that has been destroyed" do
        environment.destroy!
        expect do
          sync.call(resources: [])
        end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_environment") }
      end

      [ nil, {}, "resources" ].each do |records|
        it "rejects a non-array input of #{records.inspect}" do
          expect do
            sync.call(resources: records)
          end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_resources") }
        end
      end

      {
        "null record" => ->(_) { nil },
        "array record" => ->(_) { [] },
        "missing name" => ->(r) { r.except(:name) },
        "blank identifier" => ->(r) { r.merge(resource_id: " ") },
        "unsupported provider" => ->(r) { r.merge(provider: "azure") },
        "unsupported service" => ->(r) { r.merge(service: "lambda") },
        "numeric region" => ->(r) { r.merge(region: 123) },
        "array console URL" => ->(r) { r.merge(console_url: []) },
        "missing metadata" => ->(r) { r.except(:metadata) },
        "array metadata" => ->(r) { r.merge(metadata: []) },
        "credential metadata" => ->(r) { r.merge(metadata: { credentials: "private-test-value" }) },
        "nested metadata" => ->(r) { r.merge(metadata: { state: { token: "private-test-value" } }) },
        "incoming environment ID" => ->(r) { r.merge(environment_id: 123) },
        "incoming row ID" => ->(r) { r.merge(id: 123) },
        "conflicting field keys" => ->(r) { r.merge("name" => "Conflicting name") },
        "conflicting metadata keys" => ->(r) { r.merge(metadata: { state: "running", "state" => "stopped" }) },
        "non-string field key" => ->(r) { r.merge(123 => "invalid") }
      }.each do |description, malformed_record|
        it "rejects #{description} without exposing values or writing the batch" do
          original = inventory_snapshot
          expect do
            sync.call(resources: [ s3_record, malformed_record.call(ec2_record) ])
          end.to raise_error(ResourceSync::Error) do |error|
            expect(error.code).to eq("invalid_resource")
            expect(error.message).not_to include("private-test-value")
          end
          expect(inventory_snapshot).to eq(original)
        end
      end

      it "rejects S3 metadata outside the live-discovery contract" do
        expect do
          sync.call(resources: [ s3_record.merge(metadata: { purpose: "Demo-only attribute" }) ])
        end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_resource") }
      end
    end

    describe "atomic failure handling" do
      shared_examples "a rolled-back batch" do |expected_code|
        it "rolls back earlier inserts and updates while allowing the caller to record the failure" do
          sync.call(resources: [ ec2_record ])
          original = inventory_snapshot
          scan = environment.scans.create!(resource_types: %w[ec2 s3], started_at: Time.current)

          Resource.transaction do
            expect do
              sync.call(resources: [ ec2_record.merge(name: "Should roll back"), s3_record,
                s3_record.merge(resource_id: "reject-example-bucket") ])
            end.to raise_error(ResourceSync::Error) do |error|
              expect(error.code).to eq(expected_code)
              expect(error.message).not_to include("private-test-value")
              scan.update!(status: "failed", completed_at: Time.current,
                error_details: [ { resource_type: "persistence", code: error.code, message: error.message } ])
            end

            expect(inventory_snapshot).to eq(original)
          end

          expect(scan.reload.status).to eq("failed")
          expect(scan.error_details.first.fetch("code")).to eq(expected_code)
        end
      end

      context "when PostgreSQL rejects a later write" do
        before do
          # A real database failure exercises recovery from PostgreSQL's aborted
          # transaction state. This temporary constraint rolls back with the spec.
          Resource.connection.add_check_constraint :resources,
            "resource_id <> 'reject-example-bucket'",
            name: "rspec_reject_private_test_value"
        end

        include_examples "a rolled-back batch", "persistence_failed"
      end

      context "when model validation rejects a later record" do
        let(:reject_record) do
          ->(record) do
            if record.resource_id == "reject-example-bucket"
              record.errors.add(:base, "private-test-value")
            end
          end
        end

        before { Resource.set_callback(:validate, :before, reject_record) }
        after { Resource.skip_callback(:validate, :before, reject_record) }

        include_examples "a rolled-back batch", "invalid_resource"
      end
    end
  end

  def inventory_snapshot
    Resource.order(:id).map(&:attributes)
  end
end
