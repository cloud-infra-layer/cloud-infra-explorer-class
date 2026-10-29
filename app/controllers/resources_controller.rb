class ResourcesController < ApplicationController
  def index
    service = params[:service]
    raise ActionController::RoutingError, "Not Found" if service.present? && !%w[ec2 s3].include?(service)

    @page_title = service.present? ? "#{service.upcase} Resources" : "Resources"
    @resources = Resource.where(provider: "aws")
    @resources = @resources.where(service: service) if service.present?
    @resources = @resources.order(:name, :id)
  end
end
