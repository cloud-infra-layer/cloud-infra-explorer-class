class ResourcesController < ApplicationController
  before_action :require_personalization_access!, only: %i[pin unpin hide restore]

  def index
    service = params[:service]
    raise ActionController::RoutingError, "Not Found" if service.present? && !Resource::SERVICES.include?(service)

    query = params[:q]
    return head :bad_request unless query.nil? || query.is_a?(String)

    @query = query.to_s.strip
    @service = service
    @selected_categories = selected_categories
    @category_filter_active = category_filter_active?
    @listing_filters = listing_filters
    @personalization_enabled = personalization_enabled?
    @page_title = "Inventory"

    @resources = Resource.where(provider: "aws")
    if @service.present?
      @resources = @resources.where(service: @service)
    else
      services = @selected_categories.flat_map { |key| Resource.services_for_category(key) }
      @resources = @resources.where(service: services)
    end
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

  def selected_categories
    requested = requested_categories
    return Resource::CATEGORIES.keys if requested.empty?

    invalid = requested - Resource::CATEGORIES.keys
    raise ActionController::RoutingError, "Not Found" if invalid.any?

    requested
  end

  def requested_categories
    values = []
    values.concat(Array(params[:categories]))
    values << params[:category] if params[:category].present?
    values.map(&:to_s).uniq
  end

  def category_filter_active?
    requested_categories.any?
  end

  def listing_filters
    filters = {}
    query = params[:q]
    filters[:q] = query.strip if query.is_a?(String) && query.strip.present?
    filters[:service] = params[:service] if Resource::SERVICES.include?(params[:service])

    categories = requested_categories.select { |key| Resource::CATEGORIES.key?(key) }
    if categories.any?
      if categories.size == 1
        filters[:category] = categories.first
      else
        filters[:categories] = categories
      end
    end

    filters
  end
end
