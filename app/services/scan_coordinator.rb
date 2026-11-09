class ScanCoordinator
  RESOURCE_TYPES = %w[ec2 s3].freeze
  SAFE_FAILURE = {
    "resource_type" => "connection",
    "code" => "discovery_failed",
    "message" => "Resource discovery could not be completed."
  }.freeze

  def initialize(environment:, adapter: CloudProvider::Adapter.new, sync_factory: ->(environment) { ResourceSync.new(environment: environment) })
    @environment = environment
    @adapter = adapter
    @sync_factory = sync_factory
  end

  def call(resource_types: [ "ec2", "s3" ])
    unless @environment.is_a?(Environment) && @environment.persisted?
      raise ArgumentError, "A persisted environment is required."
    end
    unless resource_types.is_a?(Array) && resource_types.any? &&
        resource_types.uniq == resource_types && resource_types.all? { |type| RESOURCE_TYPES.include?(type) }
      raise ArgumentError, "Select unique supported resource types."
    end

    scan = @environment.scans.create!(resource_types: resource_types, started_at: Time.current)

    begin
      result = @adapter.list_resources(
        provider: @environment.provider, region: @environment.region, resource_types: resource_types
      )
      resources, errors = validate_result(result, resource_types)

      failed_types = errors.map { |error| error.fetch("resource_type") }
      successful_types = failed_types.include?("connection") ? [] : resource_types - failed_types
      successful_resources = resources.select { |resource| successful_types.include?(resource_service(resource)) }

      # Discovery errors never erase stored inventory, and failed services
      # must never write partially discovered resources.
      counts = @sync_factory.call(@environment).call(resources: successful_resources)
      status = if errors.empty?
        "completed"
      elsif successful_types.empty?
        "failed"
      else
        "partial"
      end
      finish(scan, status: status, discovered: successful_resources.size, counts: counts, errors: errors)
    rescue ResourceSync::Error => error
      finish(scan, status: "failed", discovered: 0, counts: { created: 0, updated: 0 },
        errors: [ { "resource_type" => "persistence", "code" => error.code, "message" => error.message } ])
    rescue StandardError
      # Avoid leaking raw SDK exceptions, request data, or credentials into scan history.
      finish(scan, status: "failed", discovered: 0, counts: { created: 0, updated: 0 },
        errors: [ SAFE_FAILURE ])
    end

    scan
  end

  private

  def validate_result(result, requested)
    raise ArgumentError unless result.is_a?(Hash)
    resources = result[:resources] || result["resources"]
    errors = result[:errors] || result["errors"]
    raise ArgumentError unless resources.is_a?(Array) && errors.is_a?(Array)

    normalized_errors = errors.map do |error|
      raise ArgumentError unless error.is_a?(Hash)
      record = error.stringify_keys
      raise ArgumentError unless record.keys.sort == Scan::ERROR_FIELDS.sort &&
        record.values.all? { |value| value.is_a?(String) && value.present? } &&
        (requested + [ "connection" ]).include?(record.fetch("resource_type"))
      record
    end
    raise ArgumentError if normalized_errors.map { |error| error.fetch("resource_type") }.uniq.size != normalized_errors.size

    # A connection-wide error invalidates all services, not just one.
    if normalized_errors.any? { |error| error.fetch("resource_type") == "connection" }
      return [ [], normalized_errors ]
    end

    resources.each do |resource|
      raise ArgumentError unless resource.is_a?(Hash) && requested.include?(resource_service(resource))
    end
    [ resources, normalized_errors ]
  end

  def resource_service(resource)
    resource[:service] || resource["service"]
  end

  def finish(scan, status:, discovered:, counts:, errors:)
    scan.update!(
      status: status, completed_at: Time.current, discovered_count: discovered,
      created_count: counts.fetch(:created), updated_count: counts.fetch(:updated),
      error_details: errors
    )
  end
end
