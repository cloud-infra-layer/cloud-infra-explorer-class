class DashboardController < ApplicationController
  def index
    resources = Resource.where(provider: "aws", service: %w[ec2 s3])
      .includes(:environment)
      .order(:name, :id)
      .group_by(&:service)

    @resources_by_service = {
      "ec2" => resources.fetch("ec2", []),
      "s3" => resources.fetch("s3", [])
    }
    @resource_counts = @resources_by_service.transform_values(&:size)
    @scan_enabled = ENV["ENABLE_MANUAL_SCANS"] == "true" &&
      ENV["SCAN_ADMIN_USERNAME"].present? && ENV["SCAN_ADMIN_PASSWORD"].present?
    @environments = Environment.order(:name) if @scan_enabled
  end
end
