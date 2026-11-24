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
    pinned = params[:pinned]
    return head :bad_request unless [ nil, "", "1" ].include?(pinned)

    @query = query.to_s.strip
    @service = service
    @pinned_only = @visibility == "visible" && pinned == "1"
    @listing_filters = listing_filters
    @personalization_enabled = personalization_enabled?

    @page_title = service.present? ? "#{service.upcase} Resources" : "Resources"
    @resources = Resource.where(provider: "aws")
    @resources = @visibility == "hidden" ? @resources.hidden : @resources.visible
    @resources = @resources.where(pinned: true) if @pinned_only
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

  def personalization_enabled?
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] == "true"
  end

  def require_personalization_access!
    return if personalization_enabled?

    head :not_found
  end

  def update_personalization(attribute, value, message)
    resource = Resource.find(params[:id])
    # Only the action's one field is writable; request attributes are never assigned.
    resource.update!(attribute => value)
    redirect_to resources_path(listing_filters), status: :see_other, notice: message
  end

  def listing_filters
    filters = {}
    query = params[:q]
    filters[:q] = query.strip if query.is_a?(String) && query.strip.present?
    filters[:service] = params[:service] if %w[ec2 s3].include?(params[:service])
    if params[:visibility] == "hidden"
      filters[:visibility] = "hidden"
    elsif [ nil, "", "visible" ].include?(params[:visibility]) && params[:pinned] == "1"
      filters[:pinned] = "1"
    end
    filters
  end
end
