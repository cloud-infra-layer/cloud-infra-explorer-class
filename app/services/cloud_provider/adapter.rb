require "aws-sdk-ec2"
require "aws-sdk-s3"
require "aws-sdk-rds"
require "aws-sdk-bedrock"
require "aws-sdk-cloudwatch"
require "aws-sdk-costexplorer"
require "uri"

module CloudProvider
  class Adapter
    InvalidResource = Class.new(StandardError)
    private_constant :InvalidResource

    CREDENTIAL_ERRORS = [
      Aws::Errors::MissingCredentialsError, Aws::Errors::NoSuchProfileError,
      Aws::Errors::NoSourceProfileError, Aws::Errors::NoSourceCredentialsError,
      Aws::Errors::InvalidLoginToken, Aws::Errors::InvalidSSOToken,
      Aws::Errors::InvalidSSOCredentials, Aws::Errors::InvalidProcessCredentialsPayload
    ].freeze

    EC2_MONTHLY_USD = {
      "t3.micro" => "7.50",
      "t3.small" => "15.00",
      "t3.medium" => "30.00",
      "t4g.micro" => "6.00",
      "m5.large" => "70.00"
    }.freeze

    RDS_MONTHLY_USD = {
      "db.t4g.micro" => "12.00",
      "db.t3.micro" => "15.00",
      "db.t3.small" => "30.00"
    }.freeze

    # A factory keeps client creation lazy and lets tests avoid real credentials.
    def initialize(
      ec2_client_factory: ->(region) {
        Aws::EC2::Client.new(region: region, retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      },
      s3_client_factory: ->(region) {
        Aws::S3::Client.new(region: region, retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      },
      rds_client_factory: ->(region) {
        Aws::RDS::Client.new(region: region, retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      },
      bedrock_client_factory: ->(region) {
        Aws::Bedrock::Client.new(region: region, retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      },
      cloudwatch_client_factory: ->(region) {
        Aws::CloudWatch::Client.new(region: region, retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      },
      cost_explorer_client_factory: -> {
        Aws::CostExplorer::Client.new(region: "us-east-1", retry_limit: 2, http_open_timeout: 5, http_read_timeout: 15)
      }
    )
      @ec2_client_factory = ec2_client_factory
      @s3_client_factory = s3_client_factory
      @rds_client_factory = rds_client_factory
      @bedrock_client_factory = bedrock_client_factory
      @cloudwatch_client_factory = cloudwatch_client_factory
      @cost_explorer_client_factory = cost_explorer_client_factory
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
        service_result = discover(type, region)
        result[:resources].concat(service_result[:resources])
        result[:errors].concat(service_result[:errors])
      end
      result
    end

    # Cost Explorer is account/billing data, not inventory. Returns normalized cost rows.
    def list_costs(connection_context)
      unless connection_context.is_a?(Hash)
        return cost_failure("invalid_context", "Connection context must be a hash.")
      end

      provider = connection_context[:provider] || connection_context["provider"]
      start_date = connection_context[:start_date] || connection_context["start_date"]
      end_date = connection_context[:end_date] || connection_context["end_date"]
      granularity = connection_context[:granularity] || connection_context["granularity"] || "MONTHLY"

      unless provider == "aws" && start_date.is_a?(String) && end_date.is_a?(String) &&
          CostSnapshot::GRANULARITIES.include?(granularity)
        return cost_failure("invalid_context", "Provide provider aws, ISO dates, and DAILY or MONTHLY granularity.")
      end

      client = @cost_explorer_client_factory.call
      response = client.get_cost_and_usage(
        time_period: { start: start_date, end: end_date },
        granularity: granularity,
        metrics: [ "UnblendedCost" ],
        group_by: [ { type: "DIMENSION", key: "SERVICE" } ]
      )

      costs = []
      response.results_by_time.each do |period|
        period.groups.each do |group|
          service_code = group.keys.first
          next unless service_code.is_a?(String) && service_code.present?

          amount = group.metrics["UnblendedCost"]&.amount
          next if amount.nil?

          costs << {
            period_start: period.time_period.start,
            period_end: Date.iso8601(period.time_period.end).prev_day.iso8601,
            granularity: granularity,
            service_code: service_code,
            amount: amount.to_s,
            currency: group.metrics["UnblendedCost"].unit || "USD"
          }
        end
      end
      { costs: costs, errors: [] }
    rescue *CREDENTIAL_ERRORS
      cost_failure("credentials_unavailable", "AWS credentials are unavailable. Sign in again and check your AWS profile.")
    rescue Aws::Errors::ServiceError
      cost_failure("aws_api_error", "AWS could not complete cost discovery. Check permissions, then retry.")
    rescue Seahorse::Client::NetworkingError
      cost_failure("network_error", "AWS could not be reached. Check your connection and retry.")
    rescue ArgumentError, Date::Error
      cost_failure("invalid_context", "Provide provider aws, ISO dates, and DAILY or MONTHLY granularity.")
    end

    private

    def discover(type, region)
      case type
      when "ec2" then list_ec2(region)
      when "s3" then list_s3(region)
      when "rds" then list_rds(region)
      when "bedrock" then list_bedrock(region)
      else failure(type, "unsupported_resource_type", "This resource type is not supported.")
      end
    rescue InvalidResource
      failure(type, "invalid_resource", "AWS returned incomplete or inconsistent resource identity or region data. Retry discovery.")
    rescue *CREDENTIAL_ERRORS
      failure(type, "credentials_unavailable", "AWS credentials are unavailable. Sign in again and check your AWS profile.")
    rescue Aws::Errors::ServiceError
      # Never expose SDK messages: they may contain account details or request data.
      failure(type, "aws_api_error", "AWS could not complete discovery. Check your session and read-only permissions, then retry.")
    rescue Seahorse::Client::NetworkingError
      failure(type, "network_error", "AWS could not be reached. Check your connection and retry.")
    end

    def list_ec2(region)
      client = @ec2_client_factory.call(region)
      cloudwatch = @cloudwatch_client_factory.call(region)
      resources = []
      client.describe_instances(max_results: 1000).each_page do |page|
        page.reservations.each do |reservation|
          reservation.instances.each { |instance| resources << normalize_instance(instance, region, cloudwatch) }
        end
      end
      { resources: resources, errors: [] }
    end

    def list_s3(region)
      client = @s3_client_factory.call(region)
      cloudwatch = @cloudwatch_client_factory.call(region)
      resources = []
      client.list_buckets(bucket_region: region, max_buckets: 1000).each_page do |page|
        page.buckets.each do |bucket|
          raise InvalidResource unless bucket.name.is_a?(String) && !bucket.name.strip.empty? && bucket.bucket_region == region

          name = URI.encode_www_form_component(bucket.name)
          creation = bucket.creation_date&.utc&.iso8601
          size_bytes, object_count = s3_cloudwatch_stats(cloudwatch, bucket.name)
          resources << {
            provider: "aws", resource_id: bucket.name, service: "s3", name: bucket.name,
            region: bucket.bucket_region,
            metadata: {
              creation_date: creation,
              size_bytes: size_bytes,
              object_count: object_count
            },
            console_url: Aws::Partitions.partition("aws").region?(region) ?
              "https://s3.console.aws.amazon.com/s3/buckets/#{name}?region=#{region}&tab=objects" : nil
          }
        end
      end
      { resources: resources, errors: [] }
    end

    def list_rds(region)
      client = @rds_client_factory.call(region)
      resources = []
      client.describe_db_instances(max_records: 100).each_page do |page|
        page.db_instances.each { |instance| resources << normalize_db_instance(instance, region) }
      end
      { resources: resources, errors: [] }
    end

    def list_bedrock(region)
      client = @bedrock_client_factory.call(region)
      resources = []
      client.list_foundation_models.model_summaries.each do |model|
        resources << normalize_bedrock_model(model, region)
      end
      { resources: resources, errors: [] }
    end

    def normalize_instance(instance, region, cloudwatch)
      raise InvalidResource unless instance.instance_id.is_a?(String) && !instance.instance_id.strip.empty?

      name = instance.tags.find { |tag| tag.key == "Name" }&.value
      name = instance.instance_id if name.nil? || name.strip.empty?
      instance_id = URI.encode_www_form_component(instance.instance_id)
      instance_type = instance.instance_type

      {
        provider: "aws",
        resource_id: instance.instance_id,
        service: "ec2",
        name: name,
        region: region,
        metadata: {
          instance_type: instance_type,
          state: instance.state&.name,
          cpu_utilization_pct: cloudwatch_average(
            cloudwatch,
            namespace: "AWS/EC2",
            metric_name: "CPUUtilization",
            dimensions: [ { name: "InstanceId", value: instance.instance_id } ]
          ),
          estimated_monthly_cost_usd: EC2_MONTHLY_USD[instance_type]
        },
        console_url: console_url(region, "ec2", instance_id)
      }
    end

    def normalize_db_instance(instance, region)
      resource_id = instance.db_instance_identifier
      raise InvalidResource unless resource_id.is_a?(String) && !resource_id.strip.empty?

      storage = instance.allocated_storage
      multi_az = instance.multi_az.nil? ? nil : instance.multi_az.to_s
      instance_class = instance.db_instance_class

      {
        provider: "aws",
        resource_id: resource_id,
        service: "rds",
        name: resource_id,
        region: region,
        metadata: {
          engine: instance.engine,
          engine_version: instance.engine_version,
          instance_class: instance_class,
          status: instance.db_instance_status,
          multi_az: multi_az,
          storage_gb: storage.nil? ? nil : storage.to_s,
          estimated_monthly_cost_usd: RDS_MONTHLY_USD[instance_class]
        },
        console_url: console_url(region, "rds", URI.encode_www_form_component(resource_id))
      }
    end

    def normalize_bedrock_model(model, region)
      model_id = model.model_id
      raise InvalidResource unless model_id.is_a?(String) && !model_id.strip.empty?

      modalities = Array(model.input_modalities).map(&:to_s).join(",")
      modalities = nil if modalities.empty?
      lifecycle = model.model_lifecycle&.status&.to_s

      {
        provider: "aws",
        resource_id: model_id,
        service: "bedrock",
        name: model.model_name.presence || model_id,
        region: region,
        metadata: {
          provider_name: model.provider_name,
          lifecycle_status: lifecycle,
          input_modalities: modalities,
          estimated_monthly_cost_usd: nil
        },
        console_url: Aws::Partitions.partition("aws").region?(region) ?
          "https://#{region}.console.aws.amazon.com/bedrock/home?region=#{region}#/models" : nil
      }
    end

    def s3_cloudwatch_stats(cloudwatch, bucket_name)
      size = cloudwatch_average(
        cloudwatch,
        namespace: "AWS/S3",
        metric_name: "BucketSizeBytes",
        dimensions: [
          { name: "BucketName", value: bucket_name },
          { name: "StorageType", value: "StandardStorage" }
        ],
        statistic: "Average",
        period_days: 3
      )
      count = cloudwatch_average(
        cloudwatch,
        namespace: "AWS/S3",
        metric_name: "NumberOfObjects",
        dimensions: [
          { name: "BucketName", value: bucket_name },
          { name: "StorageType", value: "AllStorageTypes" }
        ],
        statistic: "Average",
        period_days: 3
      )
      [ size && size.to_i.to_s, count && count.to_i.to_s ]
    end

    def cloudwatch_average(cloudwatch, namespace:, metric_name:, dimensions:, statistic: "Average", period_days: 1)
      end_time = Time.now.utc
      start_time = end_time - period_days * 24 * 60 * 60
      response = cloudwatch.get_metric_statistics(
        namespace: namespace,
        metric_name: metric_name,
        dimensions: dimensions,
        start_time: start_time,
        end_time: end_time,
        period: period_days * 24 * 60 * 60,
        statistics: [ statistic ]
      )
      point = response.datapoints.max_by(&:timestamp)
      return unless point

      value = point.average || point.maximum || point.sum
      return if value.nil?

      format("%.2f", value)
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError
      nil
    end

    def console_url(region, service, encoded_id)
      return unless Aws::Partitions.partition("aws").region?(region)

      case service
      when "ec2"
        "https://#{region}.console.aws.amazon.com/ec2/home?region=#{region}#InstanceDetails:instanceId=#{encoded_id}"
      when "rds"
        "https://#{region}.console.aws.amazon.com/rds/home?region=#{region}#database:id=#{encoded_id};is-cluster=false"
      end
    end

    def failure(type, code, message)
      { resources: [], errors: [ { resource_type: type, code: code, message: message } ] }
    end

    def cost_failure(code, message)
      { costs: [], errors: [ { resource_type: "cost", code: code, message: message } ] }
    end
  end
end
