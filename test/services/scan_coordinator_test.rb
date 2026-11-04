
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

  test "calls adapter with environment connection context" do
    environment = environments(:course_development)
    adapter = FakeAdapter.new(resources: [], errors: [])

    result = ScanCoordinator.new(
      environment: environment,
      adapter: adapter
    ).call

    assert_equal(
      {
        provider: "aws",
        region: "us-east-1",
        resource_types: [ "ec2" ]
      },
      adapter.received_context
    )

    assert_equal({ resources: [], errors: [] }, result)
  end

  test "returns discovered resources from adapter" do
    environment = environments(:course_testing)

    resource = {
      provider: "aws",
      resource_id: "i-1234567890",
      service: "ec2",
      name: "test-server",
      region: "us-west-2",
      metadata: {
        instance_type: "t3.micro",
        state: "running"
      },
      console_url: nil
    }

    adapter = FakeAdapter.new(
      resources: [ resource ],
      errors: []
    )

    result = ScanCoordinator.new(
      environment: environment,
      adapter: adapter
    ).call

    assert_equal [ resource ], result[:resources]
    assert_empty result[:errors]

    assert_equal "us-west-2", adapter.received_context[:region]
  end

  test "preserves structured adapter errors" do
    environment = environments(:course_development)

    error = {
      resource_type: "ec2",
      code: "credentials_unavailable",
      message: "AWS credentials are unavailable."
    }

    adapter = FakeAdapter.new(
      resources: [],
      errors: [ error ]
    )

    result = ScanCoordinator.new(
      environment: environment,
      adapter: adapter
    ).call

    assert_empty result[:resources]
    assert_equal [ error ], result[:errors]
  end
end
