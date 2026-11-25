require "spec_helper"
require "aws-sdk-cloudwatch"
require_relative "../../../app/services/cloud_provider/adapter"

# Stubbed SDK clients keep discovery coverage independent of Rails, PostgreSQL,
# credentials, and the network. Both factories are always explicitly supplied.
RSpec.describe CloudProvider::Adapter do
  let(:region) { "us-east-2" }
  let(:ec2) { Aws::EC2::Client.new(region: region, stub_responses: true) }
  let(:s3) { Aws::S3::Client.new(region: region, stub_responses: true) }
  let(:cloudwatch) { Aws::CloudWatch::Client.new(region: region, stub_responses: true) }
  let(:adapter) do
    described_class.new(
      ec2_client_factory: ->(requested) { expect(requested).to eq(region); ec2 },
      s3_client_factory: ->(requested) { expect(requested).to eq(region); s3 },
      cloudwatch_client_factory: ->(requested) { expect(requested).to eq(region); cloudwatch })
  end
  let(:request_context) { { provider: "aws", region: region, resource_types: %w[ec2 s3] } }
  let(:instance) do
    { instance_id: "i-rspec", instance_type: "t3.micro", state: { name: "running" },
      tags: [ { key: "Name", value: "Course server" }, { key: "Secret", value: "private-tag-value" } ] }
  end
  let(:bucket) { { name: "rspec-bucket", bucket_region: region } }

  def discover(*services)
    adapter.list_resources(request_context.merge(resource_types: services))
  end

  def expect_safe_failure(result, service, code)
    expect(result[:resources]).to be_empty
    expect(result[:errors].size).to eq(1)
    expect(result[:errors].first).to include(resource_type: service, code: code)
    expect(result[:errors].first.keys).to contain_exactly(:resource_type, :code, :message)
    expect(result[:errors].first[:message]).not_to be_empty
    expect(result.to_s).not_to include("sensitive response")
  end

  before do
    ec2.stub_responses(:describe_instances, reservations: [ { instances: [ instance ] } ])
    s3.stub_responses(:list_buckets, buckets: [ bucket ])
  end

  it "returns only the seven discovery fields, stable identities, and allowlisted metadata" do
    first = discover("ec2", "s3")
    expect(first[:errors]).to be_empty
    expect(first[:resources]).to eq([
      { provider: "aws", resource_id: "i-rspec", service: "ec2", name: "Course server", region: region,
        metadata: { instance_type: "t3.micro", state: "running", cpu_utilization_pct: nil, estimated_monthly_cost_usd: "7.50" },
        console_url: "https://#{region}.console.aws.amazon.com/ec2/home?region=#{region}#InstanceDetails:instanceId=i-rspec" },
      { provider: "aws", resource_id: "rspec-bucket", service: "s3", name: "rspec-bucket", region: region,
        metadata: { creation_date: nil, size_bytes: nil, object_count: nil },
        console_url: "https://s3.console.aws.amazon.com/s3/buckets/rspec-bucket?region=#{region}&tab=objects" }
    ])
    expect(first.to_s).not_to include("private-tag-value", "pinned", "hidden")
    expect(discover("ec2", "s3")).to eq(first)
  end

  [ [], [ { key: "Name", value: "  " } ] ].each do |tags|
    it "falls back to the EC2 identifier for tags #{tags.inspect}" do
      ec2.stub_responses(:describe_instances, reservations: [ { instances: [ instance.merge(tags: tags) ] } ])
      expect(discover("ec2")[:resources].first[:name]).to eq("i-rspec")
    end
  end

  it "reads every EC2 page and reservation with the requested page size" do
    ec2.stub_responses(:describe_instances, [
      { reservations: [ { instances: [ instance ] } ], next_token: "next" },
      { reservations: [ { instances: [ instance.merge(instance_id: "i-second") ] },
        { instances: [ instance.merge(instance_id: "i-third") ] } ] }
    ])
    result = discover("ec2")
    expect(result[:errors]).to be_empty
    expect(result[:resources].map { |r| r[:resource_id] }).to eq(%w[i-rspec i-second i-third])
    expect(ec2.api_requests.map { |r| r[:params] }).to eq([ { max_results: 1000 }, { max_results: 1000, next_token: "next" } ])
    expect(s3.api_requests).to be_empty
  end

  it "filters S3 by region and reads every page without per-bucket calls" do
    s3.stub_responses(:list_buckets, [
      { buckets: [ bucket ], continuation_token: "next" },
      { buckets: [ bucket.merge(name: "second-bucket") ] }
    ])
    result = discover("s3")
    expect(result[:errors]).to be_empty
    expect(result[:resources].map { |r| r[:resource_id] }).to eq(%w[rspec-bucket second-bucket])
    expect(s3.api_requests.map { |r| r[:operation_name] }).to eq([ :list_buckets, :list_buckets ])
    expect(s3.api_requests.map { |r| r[:params] }).to eq([
      { bucket_region: region, max_buckets: 1000 },
      { bucket_region: region, max_buckets: 1000, continuation_token: "next" }
    ])
    expect(ec2.api_requests).to be_empty
  end

  %w[eu-west-1 ap-southeast-2 cn-north-1].each do |requested_region|
    context "in #{requested_region}" do
      let(:region) { requested_region }

      it "honors the region and omits commercial console links in other partitions" do
        result = discover("ec2", "s3")
        expect(result[:errors]).to be_empty
        expect(result[:resources].map { |r| r[:region] }).to eq([ region, region ])
        result[:resources].each do |resource|
          if region == "cn-north-1"
            expect(resource[:console_url]).to be_nil
          else
            expect(resource[:console_url]).to include("region=#{region}")
          end
        end
      end
    end
  end

  [ nil, "", " " ].each do |identifier|
    it "discards EC2 results when an instance ID is #{identifier.inspect}" do
      ec2.stub_responses(:describe_instances, reservations: [ { instances: [ instance, instance.merge(instance_id: identifier) ] } ])
      expect_safe_failure(discover("ec2"), "ec2", "invalid_resource")
    end
  end

  [ { name: nil }, { name: " " }, { bucket_region: nil }, { bucket_region: "" }, { bucket_region: "eu-west-1" } ].each do |invalid|
    it "discards earlier S3 pages when a later bucket has #{invalid.inspect}" do
      s3.stub_responses(:list_buckets, [
        { buckets: [ bucket ], continuation_token: "next" }, { buckets: [ bucket.merge(invalid) ] }
      ])
      expect_safe_failure(discover("s3"), "s3", "invalid_resource")
    end
  end

  %w[ec2 s3].each do |service|
    context "#{service} failures" do
      let(:client) { service == "ec2" ? ec2 : s3 }
      let(:operation) { service == "ec2" ? :describe_instances : :list_buckets }

      [ "api", "network" ].each do |failure|
        it "discards earlier pages and sanitizes a later #{failure} error" do
          first_page = service == "ec2" ? { reservations: [ { instances: [ instance ] } ], next_token: "next" } :
            { buckets: [ bucket ], continuation_token: "next" }
          error = if failure == "network"
            Seahorse::Client::NetworkingError.new(IOError.new("sensitive response"))
          elsif service == "ec2"
            Aws::EC2::Errors::UnauthorizedOperation.new(nil, "sensitive response")
          else
            Aws::S3::Errors::AccessDenied.new(nil, "sensitive response")
          end
          client.stub_responses(operation, [ first_page, error ])
          expect_safe_failure(discover(service), service, failure == "network" ? "network_error" : "aws_api_error")
        end
      end

      # Explicit expected set: changing the production allowlist cannot silently
      # remove one of these regression cases.
      [ Aws::Errors::MissingCredentialsError, Aws::Errors::NoSuchProfileError,
        Aws::Errors::NoSourceProfileError, Aws::Errors::NoSourceCredentialsError,
        Aws::Errors::InvalidLoginToken, Aws::Errors::InvalidSSOToken,
        Aws::Errors::InvalidSSOCredentials, Aws::Errors::InvalidProcessCredentialsPayload ].each do |error_class|
        it "sanitizes #{error_class.name} during client creation" do
          factory = ->(_) { raise error_class, "sensitive response" }
          failing = described_class.new(ec2_client_factory: factory, s3_client_factory: factory)
          result = failing.list_resources(request_context.merge(resource_types: [ service ]))
          expect_safe_failure(result, service, "credentials_unavailable")
        end
      end

      it "sanitizes STS role-assumption failures" do
        factory = ->(_) { raise Aws::STS::Errors::AccessDenied.new(nil, "sensitive response") }
        failing = described_class.new(ec2_client_factory: factory, s3_client_factory: factory)
        expect_safe_failure(failing.list_resources(request_context.merge(resource_types: [ service ])), service, "aws_api_error")
      end
    end
  end

  %w[UnauthorizedOperation ExpiredToken RequestLimitExceeded InternalError].each do |code|
    it "returns a safe API error for EC2 #{code}" do
      ec2.stub_responses(:describe_instances, Aws::EC2::Errors.const_get(code).new(nil, "sensitive response"))
      expect_safe_failure(discover("ec2"), "ec2", "aws_api_error")
    end
  end

  %w[ec2 s3].each do |failed|
    [ %w[ec2 s3], %w[s3 ec2] ].each do |order|
      it "preserves the other service when #{failed} fails in order #{order.inspect}" do
        if failed == "ec2"
          ec2.stub_responses(:describe_instances, "UnauthorizedOperation")
        else
          s3.stub_responses(:list_buckets, "AccessDenied")
        end
        result = discover(*order)
        expect(result[:resources].map { |r| r[:service] }).to eq(order - [ failed ])
        expect(result[:errors].map { |e| e[:resource_type] }).to eq([ failed ])
      end
    end
  end

  it "distinguishes empty success, partial empty discovery, and complete failure" do
    ec2.stub_responses(:describe_instances, reservations: [])
    s3.stub_responses(:list_buckets, buckets: [])
    expect(discover("ec2", "s3")).to eq(resources: [], errors: [])
    s3.stub_responses(:list_buckets, "AccessDenied")
    expect_safe_failure(discover("ec2", "s3"), "s3", "aws_api_error")
    ec2.stub_responses(:describe_instances, "UnauthorizedOperation")
    result = discover("ec2", "s3")
    expect(result[:resources]).to be_empty
    expect(result[:errors].map { |e| e[:resource_type] }).to eq(%w[ec2 s3])
  end

  it "accepts string keys and deduplicates requested service types" do
    input = { "provider" => "aws", "region" => region, "resource_types" => %w[ec2 s3 ec2 s3] }
    expect(adapter.list_resources(input)[:errors]).to be_empty
    expect(ec2.api_requests.size).to eq(1)
    expect(s3.api_requests.size).to eq(1)
  end

  it "reports unsupported services while retaining successful discoveries" do
    result = discover("ec2", "unsupported")
    expect(result[:resources].map { |r| r[:service] }).to eq([ "ec2" ])
    expect(result[:errors].first).to include(resource_type: "unsupported", code: "unsupported_resource_type")
  end

  it "rejects invalid context before creating either client" do
    factory = ->(_) { raise "Unexpected client creation" }
    guarded = described_class.new(ec2_client_factory: factory, s3_client_factory: factory)
    invalid = [ nil, {}, request_context.merge(provider: "other") ]
    [ nil, "", " ", 123, "https://example.com", "us-east-2\n" ].each { |r| invalid << request_context.merge(region: r) }
    [ [], "ec2", [ nil ] ].each { |types| invalid << request_context.merge(resource_types: types) }
    invalid.each do |input|
      expect_safe_failure(guarded.list_resources(input), "connection", "invalid_context")
    end
  end
end
