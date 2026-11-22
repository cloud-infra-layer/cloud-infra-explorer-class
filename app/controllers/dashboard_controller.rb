
class DashboardController < ApplicationController
  def index
    resources = Resource.where(provider: "aws", service: %w[ec2 s3])
      .visible
      .includes(:environment)
      .pinned_first
      .group_by(&:service)

    @resources_by_service = {
      "ec2" => resources.fetch("ec2", []),
      "s3" => resources.fetch("s3", [])
    }

    @resource_counts = @resources_by_service.transform_values(&:size)

    @scan_enabled = ENV["ENABLE_MANUAL_SCANS"] == "true" &&
      ENV["SCAN_ADMIN_USERNAME"].present? &&
      ENV["SCAN_ADMIN_PASSWORD"].present?

    @connected_environment =
      Environment.where(provider: "aws").find_by(name: "AWS Sandbox") ||
      Environment.where(provider: "aws").order(:name).first

    @last_successful_scan = if @connected_environment
      Scan.where(
        environment: @connected_environment,
        status: "completed"
      ).order(completed_at: :desc).first
    end
  end
end
