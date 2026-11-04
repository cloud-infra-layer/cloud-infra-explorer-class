module ResourcesHelper
  def resource_metadata(resource)
    metadata = resource.metadata || {}
    fields = resource.service == "ec2" ? { "instance_type" => "Instance type", "state" => "State" } : { "purpose" => "Purpose" }
    details = fields.filter_map do |key, label|
      "#{label}: #{metadata[key]}" if metadata[key].present?
    end

    details.any? ? details.join(" · ") : "No metadata available"
  end
end
