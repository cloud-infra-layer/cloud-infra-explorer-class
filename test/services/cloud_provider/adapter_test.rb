require "minitest/autorun"
require_relative "../../../app/services/cloud_provider/adapter"

# These unit tests deliberately do not boot Rails or connect to PostgreSQL.
class CloudProviderAdapterTest < Minitest::Test
  def setup
    @client = Aws::EC2::Client.new(region: "us-east-2", stub_responses: true)
    @adapter = CloudProvider::Adapter.new(ec2_client_factory: ->(region) {
      assert_equal "us-east-2", region
      @client
    })
    @context = { provider: "aws", region: "us-east-2", resource_types: [ "ec2" ] }
  end

  def test_normalizes_instances_and_only_includes_allowlisted_metadata
    @client.stub_responses(:describe_instances, reservations: [ { instances: [ instance ] } ])
    result = @adapter.list_resources(@context)

    assert_empty result[:errors]
    assert_equal [ {
      provider: "aws", resource_id: "i-0123456789abcdef0", service: "ec2",
      name: "course-server", region: "us-east-2",
      metadata: { instance_type: "t3.micro", state: "running" },
      console_url: "https://us-east-2.console.aws.amazon.com/ec2/home?region=us-east-2#InstanceDetails:instanceId=i-0123456789abcdef0"
    } ], result[:resources]
    refute_includes result.to_s, "private-tag-value"
  end

  def test_scans_each_requested_region_with_the_same_adapter
    clients = %w[us-east-1 eu-west-1 ap-southeast-2].to_h do |region|
      client = Aws::EC2::Client.new(region: region, stub_responses: true)
      client.stub_responses(:describe_instances, reservations: [ { instances: [
        instance.merge(instance_id: "i-another", instance_type: "m7i.large",
          state: { name: "stopped" }, tags: [ { key: "Name", value: "another-workload" } ])
      ] } ])
      [ region, client ]
    end
    adapter = CloudProvider::Adapter.new(ec2_client_factory: ->(region) { clients.fetch(region) })

    clients.each do |region, client|
      result = adapter.list_resources(@context.merge(region: region))
      assert_empty result[:errors]
      resource = result[:resources].fetch(0)
      assert_equal region, resource[:region]
      assert_equal "i-another", resource[:resource_id]
      assert_equal "another-workload", resource[:name]
      assert_equal({ instance_type: "m7i.large", state: "stopped" }, resource[:metadata])
      assert_equal "https://#{region}.console.aws.amazon.com/ec2/home?region=#{region}#InstanceDetails:instanceId=i-another", resource[:console_url]
      assert_equal({}, client.api_requests.fetch(0)[:params])
    end
  end

  def test_other_partitions_do_not_receive_commercial_console_links
    client = Aws::EC2::Client.new(region: "cn-north-1", stub_responses: true)
    client.stub_responses(:describe_instances, reservations: [ { instances: [ instance ] } ])
    adapter = CloudProvider::Adapter.new(ec2_client_factory: ->(region) {
      assert_equal "cn-north-1", region
      client
    })
    result = adapter.list_resources(@context.merge(region: "cn-north-1"))
    assert_empty result[:errors]
    assert_equal "cn-north-1", result[:resources].first[:region]
    assert_nil result[:resources].first[:console_url]
  end

  def test_uses_instance_id_when_name_is_missing_or_blank
    [ [], [ { key: "Name", value: "  " } ] ].each do |tags|
      @client.stub_responses(:describe_instances, reservations: [ { instances: [ instance.merge(tags: tags) ] } ])
      assert_equal instance[:instance_id], @adapter.list_resources(@context)[:resources].first[:name]
    end
  end

  def test_successful_empty_inventory
    @client.stub_responses(:describe_instances, reservations: [])
    assert_equal({ resources: [], errors: [] }, @adapter.list_resources(@context))
  end

  def test_reads_every_page_and_reservation
    @client.stub_responses(:describe_instances, [
      { reservations: [ { instances: [ instance ] } ], next_token: "page-two" },
      { reservations: [ { instances: [ instance.merge(instance_id: "i-second") ] },
        { instances: [ instance.merge(instance_id: "i-third") ] } ] }
    ])
    result = @adapter.list_resources(@context)
    assert_empty result[:errors]
    assert_equal [ "i-0123456789abcdef0", "i-second", "i-third" ], result[:resources].map { |r| r[:resource_id] }
    assert_equal "page-two", @client.api_requests.last[:params][:next_token]
  end

  def test_discards_partial_ec2_inventory_when_later_page_fails
    @client.stub_responses(:describe_instances, [
      { reservations: [ { instances: [ instance ] } ], next_token: "page-two" },
      Aws::EC2::Errors::UnauthorizedOperation.new(nil, "sensitive AWS response")
    ])
    assert_failure(@adapter.list_resources(@context), "aws_api_error")
  end

  def test_api_errors_are_safe
    [ "UnauthorizedOperation", "ExpiredToken", "RequestLimitExceeded", "InternalError" ].each do |code|
      @client.stub_responses(:describe_instances, Aws::EC2::Errors.const_get(code).new(nil, "sensitive AWS response"))
      assert_failure(@adapter.list_resources(@context), "aws_api_error")
    end
  end

  def test_missing_or_expired_local_credentials_are_safe_even_during_client_creation
    [ Aws::Errors::MissingCredentialsError, Aws::Errors::InvalidLoginToken,
      Aws::Errors::NoSuchProfileError ].each do |error_class|
      adapter = CloudProvider::Adapter.new(ec2_client_factory: ->(_) { raise error_class, "sensitive AWS response" })
      assert_failure(adapter.list_resources(@context), "credentials_unavailable")
    end
  end

  def test_sts_failure_during_role_assumption_is_safe
    adapter = CloudProvider::Adapter.new(ec2_client_factory: ->(_) {
      raise Aws::STS::Errors::AccessDenied.new(nil, "sensitive AWS response")
    })
    assert_failure(adapter.list_resources(@context), "aws_api_error")
  end

  def test_network_failure_is_safe
    @client.stub_responses(:describe_instances, Seahorse::Client::NetworkingError.new(IOError.new("sensitive AWS response")))
    assert_failure(@adapter.list_resources(@context), "network_error")
  end

  def test_unsupported_service_is_explicit_while_ec2_can_succeed
    @client.stub_responses(:describe_instances, reservations: [ { instances: [ instance ] } ])
    result = @adapter.list_resources(@context.merge(resource_types: [ "ec2", "s3" ]))
    assert_equal 1, result[:resources].size
    assert_equal "s3", result[:errors].first[:resource_type]
    assert_equal "unsupported_resource_type", result[:errors].first[:code]
  end

  def test_invalid_context_never_calls_aws
    [ nil, {}, @context.merge(provider: "other"), @context.merge(region: nil),
      @context.merge(region: ""), @context.merge(region: "  "), @context.merge(region: 123),
      @context.merge(region: "https://example.com"), @context.merge(region: "us-east-2\n"),
      @context.merge(resource_types: []), @context.merge(resource_types: "ec2"),
      @context.merge(resource_types: [ nil ]) ].each do |context|
      result = @adapter.list_resources(context)
      assert_equal "invalid_context", result[:errors].first[:code]
      assert_empty result[:resources]
    end
    assert_empty @client.api_requests
  end

  def test_string_keys_and_duplicate_types
    @client.stub_responses(:describe_instances, reservations: [])
    context = { "provider" => "aws", "region" => "us-east-2", "resource_types" => [ "ec2", "ec2" ] }
    assert_empty @adapter.list_resources(context)[:errors]
    assert_equal 1, @client.api_requests.size
  end

  private

  def instance
    { instance_id: "i-0123456789abcdef0", instance_type: "t3.micro", state: { name: "running" },
      tags: [ { key: "Name", value: "course-server" }, { key: "Secret", value: "private-tag-value" } ] }
  end

  def assert_failure(result, code)
    assert_empty result[:resources]
    assert_equal 1, result[:errors].size
    assert_equal "ec2", result[:errors].first[:resource_type]
    assert_equal code, result[:errors].first[:code]
    refute_includes result.to_s, "sensitive AWS response"
  end
end
