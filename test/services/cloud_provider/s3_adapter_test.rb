require "minitest/autorun"
require_relative "../../../app/services/cloud_provider/adapter"

class S3AdapterTest < Minitest::Test
  def setup
    @region = "eu-west-1"
    @s3 = Aws::S3::Client.new(region: @region, stub_responses: true)
    @ec2 = Aws::EC2::Client.new(region: @region, stub_responses: true)
    @adapter = CloudProvider::Adapter.new(
      s3_client_factory: ->(region) { assert_equal @region, region; @s3 },
      ec2_client_factory: ->(region) { assert_equal @region, region; @ec2 })
    @context = { provider: "aws", region: @region, resource_types: [ "s3" ] }
  end

  def test_filters_and_paginates_buckets_without_per_bucket_requests
    @s3.stub_responses(:list_buckets, [
      { buckets: [ bucket ], continuation_token: "next" },
      { buckets: [ bucket.merge(name: "another-bucket") ] }
    ])
    result = @adapter.list_resources(@context)
    assert_empty result[:errors]
    assert_equal %w[example-bucket another-bucket], result[:resources].map { |r| r[:resource_id] }
    assert_equal({ provider: "aws", resource_id: "example-bucket", service: "s3",
      name: "example-bucket", region: @region, metadata: {},
      console_url: "https://s3.console.aws.amazon.com/s3/buckets/example-bucket?region=eu-west-1&tab=objects" }, result[:resources].first)
    assert_equal [ :list_buckets, :list_buckets ], @s3.api_requests.map { |r| r[:operation_name] }
    assert_equal({ bucket_region: @region, max_buckets: 1000 }, @s3.api_requests.first[:params])
    assert_equal({ bucket_region: @region, max_buckets: 1000, continuation_token: "next" }, @s3.api_requests.last[:params])
    assert_empty @ec2.api_requests
  end

  def test_valid_empty_inventory_and_duplicate_string_types
    @s3.stub_responses(:list_buckets, buckets: [])
    context = { "provider" => "aws", "region" => @region, "resource_types" => [ "s3", "s3" ] }
    assert_equal({ resources: [], errors: [] }, @adapter.list_resources(context))
    assert_equal 1, @s3.api_requests.size
  end

  def test_missing_region_or_identity_discards_all_s3_results
    [ { bucket_region: nil }, { bucket_region: "" }, { bucket_region: "us-east-2" },
      { name: nil }, { name: " " } ].each do |invalid|
      @s3.stub_responses(:list_buckets, [
        { buckets: [ bucket ], continuation_token: "next" },
        { buckets: [ bucket.merge(invalid) ] }
      ])
      assert_failure(@adapter.list_resources(@context), "s3", "invalid_resource")
    end
  end

  def test_later_page_errors_discard_s3_results_and_hide_sdk_details
    [ Aws::S3::Errors::AccessDenied.new(nil, "sensitive response"),
      Seahorse::Client::NetworkingError.new(IOError.new("sensitive response")) ].each do |error|
      @s3.stub_responses(:list_buckets, [ { buckets: [ bucket ], continuation_token: "next" }, error ])
      code = error.is_a?(Seahorse::Client::NetworkingError) ? "network_error" : "aws_api_error"
      assert_failure(@adapter.list_resources(@context), "s3", code)
    end
  end

  def test_credentials_and_sts_errors_during_s3_client_creation_are_safe
    [ [ Aws::Errors::MissingCredentialsError.new("sensitive response"), "credentials_unavailable" ],
      [ Aws::Errors::InvalidLoginToken.new("sensitive response"), "credentials_unavailable" ],
      [ Aws::STS::Errors::AccessDenied.new(nil, "sensitive response"), "aws_api_error" ] ].each do |error, code|
      adapter = CloudProvider::Adapter.new(s3_client_factory: ->(_) { raise error })
      assert_failure(adapter.list_resources(@context), "s3", code)
    end
  end

  def test_both_services_succeed_and_each_survives_the_others_failure
    [ nil, "ec2", "s3" ].each do |failed|
      @s3.stub_responses(:list_buckets, failed == "s3" ? "AccessDenied" : { buckets: [ bucket ] })
      @ec2.stub_responses(:describe_instances, failed == "ec2" ? "UnauthorizedOperation" :
        { reservations: [ { instances: [ { instance_id: "i-example", instance_type: "m7i.large", state: { name: "stopped" } } ] } ] })
      [ %w[ec2 s3], %w[s3 ec2] ].each do |types|
        result = @adapter.list_resources(@context.merge(resource_types: types))
        assert_equal(types.reject { |t| t == failed }.sort, result[:resources].map { |r| r[:service] }.sort)
        assert_equal(failed ? [ failed ] : [], result[:errors].map { |e| e[:resource_type] })
      end
    end
  end

  def test_successful_empty_service_remains_distinct_from_failed_service
    @ec2.stub_responses(:describe_instances, reservations: [])
    @s3.stub_responses(:list_buckets, "AccessDenied")
    result = @adapter.list_resources(@context.merge(resource_types: %w[ec2 s3]))
    assert_empty result[:resources]
    assert_equal [ "s3" ], result[:errors].map { |e| e[:resource_type] }

    @s3.stub_responses(:list_buckets, buckets: [])
    assert_equal({ resources: [], errors: [] }, @adapter.list_resources(@context.merge(resource_types: %w[ec2 s3])))
  end

  def test_both_services_fail_without_claiming_successful_empty_inventory
    @s3.stub_responses(:list_buckets, "AccessDenied")
    @ec2.stub_responses(:describe_instances, "UnauthorizedOperation")
    result = @adapter.list_resources(@context.merge(resource_types: %w[ec2 s3]))
    assert_empty result[:resources]
    assert_equal %w[ec2 s3], result[:errors].map { |e| e[:resource_type] }
  end

  def test_missing_region_never_creates_a_client_for_either_service
    adapter = CloudProvider::Adapter.new(
      ec2_client_factory: ->(_) { flunk "Unexpected EC2 client" },
      s3_client_factory: ->(_) { flunk "Unexpected S3 client" })
    [ nil, "", " ", 1, "us-east-2\n" ].each do |region|
      assert_failure(adapter.list_resources(@context.merge(region: region, resource_types: %w[ec2 s3])), "connection", "invalid_context")
    end
  end

  def test_missing_ec2_identity_discards_service_results
    @ec2.stub_responses(:describe_instances, reservations: [ { instances: [ { instance_id: "i-valid" }, {} ] } ])
    assert_failure(@adapter.list_resources(@context.merge(resource_types: [ "ec2" ])), "ec2", "invalid_resource")
  end

  def test_other_partition_has_no_incorrect_console_link
    @region = "cn-north-1"
    @s3 = Aws::S3::Client.new(region: @region, stub_responses: true)
    @s3.stub_responses(:list_buckets, buckets: [ bucket ])
    result = @adapter.list_resources(@context.merge(region: @region))
    assert_empty result[:errors]
    assert_nil result[:resources].first[:console_url]
  end

  private

  def bucket
    { name: "example-bucket", bucket_region: @region, creation_date: Time.utc(2020, 1, 1) }
  end

  def assert_failure(result, type, code)
    assert_empty result[:resources]
    assert_equal [ type ], result[:errors].map { |e| e[:resource_type] }
    assert_equal code, result[:errors].first[:code]
    refute_includes result.to_s, "sensitive response"
  end
end
