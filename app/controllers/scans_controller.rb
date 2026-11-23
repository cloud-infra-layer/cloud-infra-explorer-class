class ScansController < ApplicationController
  before_action :require_scan_access!

  def create
    environment = Environment.find(params[:environment_id])
    types = params[:resource_types]
    # Unchecked checkboxes omit resource_types, while existing clients can omit it to scan both.
    types = Scan::RESOURCE_TYPES if types.nil? && !params.key?(:scan_form)

    unless types.is_a?(Array) && types.any? && types.uniq == types &&
        types.all? { |type| Scan::RESOURCE_TYPES.include?(type) }
      return redirect_to dashboard_path(environment_id: environment.id), alert: "Select valid EC2/S3 resource types."
    end

    scan = ScanCoordinator.new(environment: environment).call(resource_types: types)
    message = case scan.status
    when "completed"
      "Scan completed: #{scan.created_count} new, #{scan.updated_count} updated resources."
    when "partial"
      "Scan partially completed. Some resources could not be discovered."
    else
      "Scan failed. Previously stored resources were preserved."
    end

    redirect_to dashboard_path(environment_id: environment.id), notice: message
  end

  private

  def require_scan_access!
    unless ENV["ENABLE_MANUAL_SCANS"] == "true" &&
        ENV["SCAN_ADMIN_USERNAME"].present? && ENV["SCAN_ADMIN_PASSWORD"].present?
      return head :not_found
    end

    authenticate_or_request_with_http_basic("Cloud Infrastructure Explorer scans") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SCAN_ADMIN_USERNAME")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SCAN_ADMIN_PASSWORD"))
    end
  end
end
