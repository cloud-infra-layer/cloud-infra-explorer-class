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

    visible_resources = @resources_by_service.values.flatten
    @pinned_resources = visible_resources.select(&:pinned?).first(8)

    @scan_enabled = ENV["ENABLE_MANUAL_SCANS"] == "true" &&
      ENV["SCAN_ADMIN_USERNAME"].present? &&
      ENV["SCAN_ADMIN_PASSWORD"].present?

    aws_environments = Environment.where(provider: "aws").order(:name, :id)
    @scan_environments = aws_environments.to_a if @scan_enabled
    @selected_environment = @scan_environments&.find { |environment| environment.id.to_s == params[:environment_id] } ||
      aws_environments.find_by(name: "AWS Sandbox") || aws_environments.first

    return unless @selected_environment

    scans = @selected_environment.scans
    @last_successful_scan = scans.where(status: "completed").order(completed_at: :desc).first
    @latest_scan = scans.order(started_at: :desc, id: :desc).first if @scan_enabled
  end
end
