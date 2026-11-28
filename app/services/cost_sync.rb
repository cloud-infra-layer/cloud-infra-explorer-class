class CostSync
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  FIELDS = %w[period_start period_end granularity service_code amount currency].freeze

  def initialize(environment:)
    @environment = environment
  end

  def call(costs:)
    unless @environment.is_a?(Environment) && @environment.persisted?
      raise Error.new("invalid_environment", "Select an existing environment before synchronizing costs.")
    end
    unless costs.is_a?(Array)
      raise Error.new("invalid_costs", "Costs must be an array of normalized cost records.")
    end

    records = costs.map { |record| normalize_record(record) }
    identities = records.map { |record| identity_for(record) }
    unless identities.uniq.size == identities.size
      raise Error.new("duplicate_cost", "The batch contains duplicate cost identities.")
    end

    counts = { created: 0, updated: 0 }
    @environment.with_lock(requires_new: true) do
      records.each do |attributes|
        snapshot = @environment.cost_snapshots.find_or_initialize_by(identity_for(attributes))
        snapshot.assign_attributes(attributes)

        if snapshot.new_record?
          snapshot.save!
          counts[:created] += 1
        elsif snapshot.changed?
          snapshot.save!
          counts[:updated] += 1
        end
      end
    end
    counts
  rescue ActiveRecord::RecordInvalid
    raise Error.new("invalid_cost", "A cost record failed validation. No costs from this batch were saved.")
  rescue ActiveRecord::ActiveRecordError
    raise Error.new("persistence_failed", "Cost synchronization failed. No costs from this batch were saved.")
  end

  private

  def normalize_record(record)
    attributes = string_keys(record)
    invalid_cost! unless (attributes.keys - FIELDS).empty?

    period_start = parse_date(attributes["period_start"])
    period_end = parse_date(attributes["period_end"])
    granularity = attributes["granularity"]
    service_code = attributes["service_code"]
    currency = attributes["currency"] || "USD"
    amount = parse_amount(attributes["amount"])

    invalid_cost! unless period_start && period_end && period_end >= period_start
    invalid_cost! unless CostSnapshot::GRANULARITIES.include?(granularity)
    invalid_cost! unless service_code.is_a?(String) && service_code.present?
    invalid_cost! unless currency == "USD"
    invalid_cost! if amount.nil?

    {
      "period_start" => period_start,
      "period_end" => period_end,
      "granularity" => granularity,
      "service_code" => service_code,
      "amount" => amount,
      "currency" => currency
    }
  end

  def string_keys(value)
    invalid_cost! unless value.is_a?(Hash)
    result = {}
    value.each do |key, item|
      invalid_cost! unless key.is_a?(String) || key.is_a?(Symbol)
      key = key.to_s
      invalid_cost! if result.key?(key)
      result[key] = item
    end
    result
  end

  def parse_date(value)
    return value if value.is_a?(Date)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    Date.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_amount(value)
    return value if value.is_a?(Numeric)
    return BigDecimal(value) if value.is_a?(String) && value.match?(/\A-?\d+(?:\.\d+)?\z/)

    nil
  end

  def identity_for(attributes)
    attributes.slice("period_start", "period_end", "granularity", "service_code")
  end

  def invalid_cost!
    raise Error.new("invalid_cost", "A cost record does not match the normalized cost contract.")
  end
end
