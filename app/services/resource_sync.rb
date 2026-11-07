class ResourceSync
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  FIELDS = %w[provider resource_id service name region metadata console_url].freeze
  REQUIRED_STRINGS = %w[provider resource_id service name].freeze
  METADATA_FIELDS = { "ec2" => %w[instance_type state], "s3" => [] }.freeze

  def initialize(environment:)
    @environment = environment
  end

  def call(resources:)
    unless @environment.is_a?(Environment) && @environment.persisted?
      raise Error.new("invalid_environment", "Select an existing environment before synchronizing resources.")
    end
    unless resources.is_a?(Array)
      raise Error.new("invalid_resources", "Resources must be an array of normalized records.")
    end

    records = resources.map { |record| normalize_record(record) }
    identities = records.map { |record| identity_for(record) }
    unless identities.uniq.size == identities.size
      raise Error.new("duplicate_resource", "The batch contains duplicate resource identities.")
    end

    counts = { created: 0, updated: 0 }
    # with_lock starts a transaction and serializes syncs for this environment.
    # requires_new also rolls back this batch if a caller rescues inside an
    # outer transaction (for example, while updating a Scan).
    @environment.with_lock(requires_new: true) do
      records.each do |attributes|
        unless attributes.fetch("provider") == @environment.provider
          raise Error.new("invalid_resource", "Resource provider must match the selected environment.")
        end

        resource = @environment.resources.find_or_initialize_by(identity_for(attributes))
        resource.assign_attributes(attributes)

        if resource.new_record?
          resource.save!
          counts[:created] += 1
        elsif resource.changed?
          resource.save!
          counts[:updated] += 1
        end
      end
    end
    counts
  rescue ActiveRecord::RecordInvalid
    raise Error.new("invalid_resource", "A resource failed validation. No resources from this batch were saved.")
  rescue ActiveRecord::ActiveRecordError
    raise Error.new("persistence_failed", "Resource synchronization failed. No resources from this batch were saved.")
  end

  private

  def normalize_record(record)
    attributes = string_keys(record)
    valid = (attributes.keys - FIELDS).empty? &&
      REQUIRED_STRINGS.all? { |key| nonblank_string?(attributes[key]) } &&
      attributes["provider"] == "aws" && METADATA_FIELDS.key?(attributes["service"]) &&
      %w[region console_url].all? { |key| attributes[key].nil? || nonblank_string?(attributes[key]) }
    invalid_resource! unless valid

    metadata = string_keys(attributes["metadata"])
    allowed_keys = METADATA_FIELDS.fetch(attributes["service"])
    unless (metadata.keys - allowed_keys).empty? && metadata.values.all? { |value| value.nil? || value.is_a?(String) }
      invalid_resource!
    end

    # Normalize optional fields so a later scan can clear an old value.
    { "region" => nil, "console_url" => nil }.merge(attributes).merge("metadata" => metadata)
  end

  def string_keys(value)
    invalid_resource! unless value.is_a?(Hash)
    result = {}
    value.each do |key, item|
      invalid_resource! unless key.is_a?(String) || key.is_a?(Symbol)
      key = key.to_s
      invalid_resource! if result.key?(key)
      result[key] = item
    end
    result
  end

  def nonblank_string?(value)
    value.is_a?(String) && value.present?
  end

  def identity_for(attributes)
    fields = %w[provider service resource_id]
    fields << "region" if attributes.fetch("service") == "ec2"
    attributes.slice(*fields)
  end

  def invalid_resource!
    raise Error.new("invalid_resource", "A resource does not match the normalized resource contract.")
  end
end
