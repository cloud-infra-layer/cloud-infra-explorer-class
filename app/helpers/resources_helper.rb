module ResourcesHelper
  CATEGORY_LABELS = { "ec2" => "Compute", "s3" => "Storage" }.freeze

  def category_label(service)
    CATEGORY_LABELS.fetch(service.to_s) { service.to_s.upcase }
  end

  def resource_metadata(resource)
    metadata = resource.metadata || {}
    fields = resource.service == "ec2" ? { "instance_type" => "Instance type", "state" => "State" } : { "purpose" => "Purpose" }
    details = fields.filter_map do |key, label|
      "#{label}: #{metadata[key]}" if metadata[key].present?
    end

    details.any? ? details.join(" · ") : "No metadata available"
  end

  def resource_status_label(resource)
    return "Hidden" if resource.hidden?
    return "Pinned" if resource.pinned?

    "Unpinned"
  end
end
