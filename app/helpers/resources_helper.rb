module ResourcesHelper
  METADATA_LABELS = {
    "ec2" => {
      "instance_type" => "Instance type",
      "state" => "State",
      "cpu_utilization_pct" => "CPU %",
      "estimated_monthly_cost_usd" => "Est. monthly USD"
    },
    "s3" => {
      "creation_date" => "Created",
      "size_bytes" => "Size (bytes)",
      "object_count" => "Objects"
    },
    "rds" => {
      "engine" => "Engine",
      "engine_version" => "Version",
      "instance_class" => "Class",
      "status" => "Status",
      "multi_az" => "Multi-AZ",
      "storage_gb" => "Storage (GB)",
      "estimated_monthly_cost_usd" => "Est. monthly USD"
    },
    "bedrock" => {
      "provider_name" => "Model provider",
      "lifecycle_status" => "Lifecycle",
      "input_modalities" => "Inputs",
      "estimated_monthly_cost_usd" => "Est. monthly USD"
    }
  }.freeze

  SERVICE_LABELS = {
    "ec2" => "EC2",
    "s3" => "S3",
    "rds" => "RDS",
    "bedrock" => "Bedrock"
  }.freeze

  PROVIDER_LABELS = {
    "aws" => "AWS"
  }.freeze

  COST_SERIES_COLORS = {
    "Amazon Elastic Compute Cloud - Compute" => "#175bb5",
    "Amazon Relational Database Service" => "#0f7b6c",
    "Amazon Simple Storage Service" => "#c27803",
    "Amazon Bedrock" => "#7c3aed"
  }.freeze

  COST_SERIES_SHORT_LABELS = {
    "Amazon Elastic Compute Cloud - Compute" => "EC2",
    "Amazon Relational Database Service" => "RDS",
    "Amazon Simple Storage Service" => "S3",
    "Amazon Bedrock" => "Bedrock"
  }.freeze

  COST_RANGE_OPTIONS = [
    [ "3M", "3M" ],
    [ "6M", "6M" ],
    [ "1Y", "1Y" ],
    [ "YTD", "YTD" ],
    [ "Max", "MAX" ]
  ].freeze

  def category_label(key_or_service)
    key = key_or_service.to_s
    return Resource::CATEGORIES.fetch(key).fetch(:label) if Resource::CATEGORIES.key?(key)

    category = Resource.category_for_service(key)
    return Resource::CATEGORIES.fetch(category).fetch(:label) if category

    key.to_s
  end

  def category_description(key)
    Resource::CATEGORIES.dig(key.to_s, :description).to_s
  end

  def service_label(service)
    SERVICE_LABELS.fetch(service.to_s) { service.to_s }
  end

  def provider_label(provider)
    PROVIDER_LABELS.fetch(provider.to_s) { provider.to_s.upcase }
  end

  def resource_metadata_entries(resource)
    metadata = resource.metadata || {}
    fields = METADATA_LABELS.fetch(resource.service, {})
    entries = [ [ "Resource ID", resource.resource_id ] ]
    entries + fields.filter_map do |key, label|
      [ label, metadata[key] ] if metadata[key].present?
    end
  end

  CATEGORY_ICON_PATHS = {
    "compute" => "M4 6h16v10H4V6Zm2 12h12v2H6v-2Z",
    "storage" => "M4 7a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v2H4V7Zm0 4h16v2H4v-2Zm0 4h16v2a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-2Z",
    "databases" => "M12 3c-4.4 0-8 1.6-8 3.5S7.6 10 12 10s8-1.6 8-3.5S16.4 3 12 3Zm-8 7.2V14c0 1.9 3.6 3.5 8 3.5s8-1.6 8-3.5v-3.8c-1.7 1.2-4.7 1.8-8 1.8s-6.3-.6-8-1.8Zm0 5.5V19c0 1.9 3.6 3.5 8 3.5s8-1.6 8-3.5v-3.3c-1.7 1.2-4.7 1.8-8 1.8s-6.3-.6-8-1.8Z",
    "ai" => "M12 2 9.5 8.5 3 9.5l5 4.2L6.5 20 12 16.8 17.5 20 16 13.7l5-4.2-6.5-1L12 2Z"
  }.freeze

  def category_icon(key)
    path = CATEGORY_ICON_PATHS.fetch(key.to_s) { "M12 4a8 8 0 1 1 0 16 8 8 0 0 1 0-16Z" }
    tag.svg(viewBox: "0 0 24 24", "aria-hidden": true, focusable: "false") do
      tag.path(d: path, fill: "currentColor")
    end
  end

  def cost_series_color(service_code)
    COST_SERIES_COLORS.fetch(service_code) { "#526176" }
  end

  def cost_series_short_label(service_code)
    COST_SERIES_SHORT_LABELS.fetch(service_code) { service_code.to_s }
  end

  def cost_series_legend_label(service_code, provider: "aws")
    "#{provider_label(provider)} #{cost_series_short_label(service_code)}"
  end
end
