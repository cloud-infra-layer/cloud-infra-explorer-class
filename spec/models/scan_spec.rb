require "rails_helper"

RSpec.describe Scan, type: :model do
  let(:environment) do
    Environment.create!(name: "RSpec environment", provider: "aws", region: "us-east-2")
  end
  let(:started_at) { Time.utc(2026, 11, 1, 12, 0, 0) }
  let(:scan) { environment.scans.build(resource_types: %w[ec2 s3], started_at: started_at) }
  let(:safe_error) do
    { "resource_type" => "s3", "code" => "aws_api_error", "message" => "S3 discovery failed." }
  end

  describe "recording a running scan" do
    it "persists the requested services, environment, and initial defaults" do
      expect { scan.save! }.to change(described_class, :count).by(1)

      expect(scan.reload).to have_attributes(
        environment: environment, status: "running", resource_types: %w[ec2 s3],
        discovered_count: 0, created_count: 0, updated_count: 0,
        error_details: [], started_at: started_at, completed_at: nil
      )
      expect(environment.scans).to include(scan)
    end

    it "rejects a completion timestamp while still running" do
      scan.completed_at = started_at

      expect(scan).not_to be_valid
      expect(scan.errors[:completed_at]).not_to be_empty
    end
  end

  describe "recording finished outcomes" do
    {
      "completed" => { discovered_count: 2, created_count: 1, updated_count: 1 },
      "partial" => { discovered_count: 1, created_count: 1, updated_count: 0 },
      "failed" => { discovered_count: 0, created_count: 0, updated_count: 0 }
    }.each do |status, counts|
      context "when the outcome is #{status}" do
        it "persists the outcome, counts, safe errors, and completion time" do
          scan.save!
          details = status == "completed" ? [] : [ safe_error ]
          scan.update!(**counts, status: status, error_details: details, completed_at: started_at + 1.second)

          expect(scan.reload).to have_attributes(
            **counts, status: status, error_details: details, completed_at: started_at + 1.second
          )
        end

        it "requires a completion time" do
          scan.status = status

          expect(scan).not_to be_valid
          expect(scan.errors[:completed_at]).not_to be_empty
        end

        it "rejects completion before the start time" do
          scan.assign_attributes(status: status, completed_at: started_at - 1.second)

          expect(scan).not_to be_valid
          expect(scan.errors[:completed_at]).not_to be_empty
        end

        it "accepts completion at the start time" do
          scan.assign_attributes(status: status, completed_at: started_at)

          expect(scan).to be_valid
        end
      end
    end

    it "can record a successful scan that discovered no resources" do
      scan.update!(status: "completed", completed_at: started_at)

      expect(scan.reload).to have_attributes(
        status: "completed", discovered_count: 0, created_count: 0, updated_count: 0, error_details: []
      )
    end
  end

  describe "required scan context" do
    { environment: nil, started_at: nil, status: "unknown" }.each do |attribute, value|
      it "rejects invalid #{attribute}" do
        scan.public_send("#{attribute}=", value)

        expect(scan).not_to be_valid
        expect(scan.errors[attribute]).not_to be_empty
      end
    end
  end

  describe "requested services" do
    [ [ "ec2" ], [ "s3" ], %w[ec2 s3], %w[s3 ec2] ].each do |types|
      it "accepts #{types.inspect}" do
        scan.resource_types = types

        expect(scan).to be_valid
      end
    end

    [ nil, [], "ec2", {}, [ "lambda" ], [ "ec2", "ec2" ], [ nil ] ].each do |types|
      it "rejects #{types.inspect}" do
        scan.resource_types = types

        expect(scan).not_to be_valid
        expect(scan.errors[:resource_types]).not_to be_empty
      end
    end
  end

  describe "resource counts" do
    %i[discovered_count created_count updated_count].each do |attribute|
      [ nil, -1, 1.5, "invalid" ].each do |value|
        it "rejects #{attribute} of #{value.inspect}" do
          scan[attribute] = value

          expect(scan).not_to be_valid
          expect(scan.errors[attribute]).not_to be_empty
        end
      end
    end
  end

  describe "stored error details" do
    it "round-trips symbol-keyed details without replacing Rails validation errors" do
      scan.error_details = [ safe_error.symbolize_keys ]
      scan.save!

      expect(scan.reload.error_details).to eq([ safe_error ])
      expect(scan.errors).to be_a(ActiveModel::Errors)

      scan.status = "unknown"
      expect(scan).not_to be_valid
      expect(scan.errors[:status]).not_to be_empty
      expect(scan.error_details).to eq([ safe_error ])
    end

    [ nil, {}, "exception", [ "exception" ], [ {} ] ].each do |details|
      it "rejects malformed error collection #{details.inspect}" do
        scan.error_details = details

        expect(scan).not_to be_valid
        expect(scan.errors[:error_details]).not_to be_empty
      end
    end

    %w[resource_type code message].each do |field|
      it "requires a nonblank string for #{field}" do
        scan.error_details = [ safe_error.merge(field => " ") ]

        expect(scan).not_to be_valid
        expect(scan.errors[:error_details]).not_to be_empty
      end
    end

    it "rejects non-string values" do
      scan.error_details = [ safe_error.merge("code" => 123) ]

      expect(scan).not_to be_valid
      expect(scan.errors[:error_details]).not_to be_empty
    end

    it "rejects extra fields such as raw exception details" do
      scan.error_details = [ safe_error.merge("raw_exception" => "Untrusted details") ]

      expect(scan).not_to be_valid
      expect(scan.errors[:error_details]).not_to be_empty
    end
  end

  describe "protecting scan history" do
    it "prevents destroying an environment with scans but no resources" do
      scan.save!

      expect(environment.resources).to be_empty
      expect(environment.destroy).to be(false)
      expect(Environment.exists?(environment.id)).to be(true)
      expect(described_class.exists?(scan.id)).to be(true)
      expect(environment.errors[:base]).not_to be_empty
    end
  end

  describe "database constraints when model validation is bypassed" do
    before { scan.save! }

    [ { status: "unknown" }, { discovered_count: -1 }, { created_count: -1 }, { updated_count: -1 } ].each do |attributes|
      it "rejects #{attributes.inspect} without changing the saved record" do
        original = scan.attributes

        expect do
          described_class.transaction(requires_new: true) { scan.update_columns(attributes) }
        end.to raise_error(ActiveRecord::StatementInvalid)

        expect(scan.reload.attributes).to eq(original)
      end
    end

    it "prevents deleting the parent directly in PostgreSQL" do
      expect do
        described_class.transaction(requires_new: true) { environment.delete }
      end.to raise_error(ActiveRecord::InvalidForeignKey)

      expect(Environment.exists?(environment.id)).to be(true)
      expect(described_class.exists?(scan.id)).to be(true)
    end

    %i[environment_id started_at].each do |attribute|
      it "rejects null #{attribute}" do
        expect do
          described_class.transaction(requires_new: true) { scan.update_columns(attribute => nil) }
        end.to raise_error(ActiveRecord::NotNullViolation)
      end
    end
  end
end
