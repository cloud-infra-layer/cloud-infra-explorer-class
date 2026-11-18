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
    if @scan_enabled
      @environments = Environment.order(:name).to_a
      environment_ids = @environments.map(&:id)
      @latest_scans = Scan.where(environment_id: environment_ids)
        .order(started_at: :desc, id: :desc)
        .group_by(&:environment_id)
        .transform_values(&:first)
    end
  end
end
