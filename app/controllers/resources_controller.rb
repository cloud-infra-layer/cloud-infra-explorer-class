class ResourcesController < ApplicationController
  before_action :require_personalization_access!, only: %i[pin unpin hide restore]

  def index
    service = params[:service]
    raise ActionController::RoutingError, "Not Found" if service.present? && !%w[ec2 s3].include?(service)

    query = params[:q]
    return head :bad_request unless query.nil? || query.is_a?(String)
    visibility = params[:visibility]
    return head :bad_request unless visibility.nil? || visibility.is_a?(String)
    @visibility = visibility.presence || "visible"
    return head :bad_request unless %w[visible hidden].include?(@visibility)

    @query = query.to_s.strip
    @service = service

    @page_title = service.present? ? "#{service.upcase} Resources" : "Resources"
    @resources = Resource.where(provider: "aws")
    @resources = @visibility == "hidden" ? @resources.hidden : @resources.visible
    @resources = @resources.where(service: service) if service.present?
    @resources = @resources.search(@query).pinned_first
  end

  def pin
    update_personalization(:pinned, true, "Resource pinned for the team.")
  end

  def unpin
    update_personalization(:pinned, false, "Resource unpinned for the team.")
  end

  def hide
    update_personalization(:hidden, true, "Resource hidden from the team's visible inventory.")
  end

  def restore
    update_personalization(:hidden, false, "Resource restored to the team's visible inventory.")
  end

  private

  def require_personalization_access!
    unless ENV["ENABLE_RESOURCE_PERSONALIZATION"] == "true" &&
        ENV["RESOURCE_ADMIN_USERNAME"].present? && ENV["RESOURCE_ADMIN_PASSWORD"].present?
      return head :not_found
    end

    authenticate_or_request_with_http_basic("Cloud Infrastructure Explorer personalization") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("RESOURCE_ADMIN_USERNAME")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("RESOURCE_ADMIN_PASSWORD"))
    end
  end

  def update_personalization(attribute, value, message)
    resource = Resource.find(params[:id])
    # Only the action's one field is writable; request attributes are never assigned.
    resource.update!(attribute => value)
    redirect_to resources_path, status: :see_other, notice: message
  end
end
