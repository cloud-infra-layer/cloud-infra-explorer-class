require "aws-sdk-ec2"
require "uri"

module CloudProvider
  class Adapter
    CREDENTIAL_ERRORS = [
      Aws::Errors::MissingCredentialsError, Aws::Errors::NoSuchProfileError,
      Aws::Errors::NoSourceProfileError, Aws::Errors::NoSourceCredentialsError,
      Aws::Errors::InvalidLoginToken, Aws::Errors::InvalidSSOToken,
      Aws::Errors::InvalidSSOCredentials, Aws::Errors::InvalidProcessCredentialsPayload
    ].freeze

    # A factory keeps client creation lazy and lets tests avoid real credentials.
    def initialize(ec2_client_factory: ->(region) {
      Aws::EC2::Client.new(region: region, retry_limit: 2,
        http_open_timeout: 5, http_read_timeout: 15)
    })
      @ec2_client_factory = ec2_client_factory
    end

    def list_resources(connection_context)
      unless connection_context.is_a?(Hash)
        return failure("connection", "invalid_context", "Connection context must be a hash.")
      end

      provider = connection_context[:provider] || connection_context["provider"]
      region = connection_context[:region] || connection_context["region"]
      types = connection_context[:resource_types] || connection_context["resource_types"]

      unless provider == "aws" && region.is_a?(String) && region.match?(/\A[a-z]{2}(?:-[a-z]+)+-\d+\z/) && types.is_a?(Array) &&
          types.any? && types.all? { |type| type.is_a?(String) && !type.strip.empty? }
        return failure("connection", "invalid_context",
          "Provide provider aws, an AWS region code, and a non-empty array of resource type strings.")
      end

      result = { resources: [], errors: [] }
      types.uniq.each do |type|
        service_result = if type == "ec2"
          list_ec2(region)
        else
          failure(type, "unsupported_resource_type", "This resource type is not supported in Sprint 1.")
        end
        result[:resources].concat(service_result[:resources])
        result[:errors].concat(service_result[:errors])
      end
      result
    end

    private

    def list_ec2(region)
      client = @ec2_client_factory.call(region)
      resources = []
      client.describe_instances.each_page do |page|
        page.reservations.each do |reservation|
          reservation.instances.each { |instance| resources << normalize_instance(instance, region) }
        end
      end
      { resources: resources, errors: [] }
    rescue *CREDENTIAL_ERRORS
      failure("ec2", "credentials_unavailable", "AWS credentials are unavailable. Sign in again and check your AWS profile.")
    rescue Aws::Errors::ServiceError
      # Never expose SDK messages: they may contain account details or request data.
      failure("ec2", "aws_api_error", "AWS could not complete EC2 discovery. Check your session and read-only permissions, then retry.")
    rescue Seahorse::Client::NetworkingError
      failure("ec2", "network_error", "AWS could not be reached. Check your connection and retry.")
    end

    def normalize_instance(instance, region)
      name = instance.tags.find { |tag| tag.key == "Name" }&.value
      name = instance.instance_id if name.nil? || name.strip.empty?
      instance_id = URI.encode_www_form_component(instance.instance_id)

      {
        provider: "aws",
        resource_id: instance.instance_id,
        service: "ec2",
        name: name,
        region: region,
        metadata: { instance_type: instance.instance_type, state: instance.state&.name },
        console_url: console_url(region, instance_id)
      }
    end

    def console_url(region, instance_id)
      # Other partitions have different consoles; omit links we cannot construct reliably.
      return unless Aws::Partitions.partition("aws").region?(region)

      "https://#{region}.console.aws.amazon.com/ec2/home?region=#{region}#InstanceDetails:instanceId=#{instance_id}"
    end

    def failure(type, code, message)
      { resources: [], errors: [ { resource_type: type, code: code, message: message } ] }
    end
  end
end
