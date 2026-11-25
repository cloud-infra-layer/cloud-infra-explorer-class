class DashboardController < ApplicationController
  COST_RANGES = %w[3M 6M 1Y YTD MAX].freeze

  def index
    visible = Resource.where(provider: "aws", service: Resource::SERVICES).visible
    @category_insights = build_category_insights(visible)

    @cost_range = COST_RANGES.include?(params[:cost_range].to_s) ? params[:cost_range].to_s : "6M"
    full_chart = build_cost_chart("MAX")
    @cost_chart = build_cost_chart(@cost_range)
    @cost_insights = build_cost_insights(full_chart)

    @scan_enabled = ENV["ENABLE_MANUAL_SCANS"] == "true"

    environments = Environment.order(:name, :id)
    @scan_environments = environments.to_a if @scan_enabled
    @connected_environment = (@scan_environments || environments).find { |environment| environment.id.to_s == params[:environment_id] } ||
      environments.find_by(name: "AWS Sandbox") || environments.first

    return unless @connected_environment

    scans = @connected_environment.scans
    @last_successful_scan = scans.where(status: "completed").order(completed_at: :desc).first
    @latest_scan = scans.order(started_at: :desc, id: :desc).first if @scan_enabled
  end

  private

  def build_category_insights(visible_scope)
    Resource::CATEGORIES.to_h do |key, config|
      resources = visible_scope.where(service: config.fetch(:services)).to_a
      [ key, {
        count: resources.size,
        pinned: resources.count(&:pinned?),
        insight: category_insight(key, resources)
      } ]
    end
  end

  def category_insight(key, resources)
    return "No stored resources yet." if resources.empty?

    case key
    when "compute"
      states = resources.map { |resource| resource.metadata.to_h["state"].to_s }
      running = states.count("running")
      stopped = states.count("stopped")
      "#{running} running · #{stopped} stopped"
    when "storage"
      objects = resources.sum { |resource| resource.metadata.to_h["object_count"].to_i }
      "#{resources.size} #{resources.one? ? 'bucket' : 'buckets'} · #{number_with_delimiter(objects)} objects"
    when "databases"
      engines = resources.map { |resource| resource.metadata.to_h["engine"].presence }.compact.uniq
      engines.any? ? "#{resources.size} instances · #{engines.map(&:capitalize).join(', ')}" : "#{resources.size} instances"
    when "ai"
      active = resources.count { |resource| resource.metadata.to_h["lifecycle_status"].to_s == "ACTIVE" }
      "#{active} active #{active == 1 ? 'model' : 'models'}"
    else
      "#{resources.size} resources"
    end
  end

  def number_with_delimiter(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end

  def build_cost_chart(range)
    snapshots = CostSnapshot
      .joins(:environment)
      .where(environments: { provider: "aws" }, granularity: "MONTHLY")
      .includes(:environment)
      .order(:period_start, :service_code)

    return { periods: [], series: [], range: range } if snapshots.empty?

    periods = filter_cost_periods(snapshots.map(&:period_start).uniq.sort, range)
    return { periods: [], series: [], range: range } if periods.empty?

    service_codes = snapshots.map(&:service_code).uniq.sort
    amounts = snapshots.index_by { |snapshot| [ snapshot.period_start, snapshot.service_code ] }
    providers = snapshots.each_with_object({}) do |snapshot, memo|
      memo[snapshot.service_code] ||= snapshot.environment.provider
    end

    series = service_codes.map do |service_code|
      {
        service_code: service_code,
        provider: providers.fetch(service_code, "aws"),
        values: periods.map { |period| amounts[[ period, service_code ]]&.amount.to_f }
      }
    end

    { periods: periods, series: series, range: range }
  end

  def filter_cost_periods(periods, range)
    return periods if periods.empty? || range == "MAX"

    anchor = periods.last
    case range
    when "3M" then periods.last(3)
    when "6M" then periods.last(6)
    when "1Y" then periods.last(12)
    when "YTD" then periods.select { |period| period.year == anchor.year }
    else periods
    end
  end

  def build_cost_insights(chart)
    periods = chart.fetch(:periods)
    series = chart.fetch(:series)
    return if periods.empty? || series.empty?

    totals_by_period = periods.each_with_index.to_h do |period, index|
      [ period, series.sum { |row| row.fetch(:values).fetch(index) } ]
    end

    current_period = periods.last
    current_total = totals_by_period.fetch(current_period)
    previous_period = current_period - 1.month
    year_ago_period = current_period - 12.months
    previous_total = totals_by_period[previous_period]
    year_ago_total = totals_by_period[year_ago_period]

    mom_pct = percent_change(previous_total, current_total)
    yoy_pct = percent_change(year_ago_total, current_total)

    last_index = periods.size - 1
    top = series.max_by { |row| row.fetch(:values).fetch(last_index) }
    top_amount = top.fetch(:values).fetch(last_index)
    top_share = current_total.positive? ? (top_amount / current_total) * 100.0 : nil

    fastest = series.filter_map do |row|
      current = row.fetch(:values).fetch(last_index)
      previous = last_index.positive? ? row.fetch(:values).fetch(last_index - 1) : nil
      next unless previous&.positive?

      { row: row, change: ((current - previous) / previous) * 100.0, amount: current }
    end.max_by { |entry| entry.fetch(:change) }

    {
      period_label: current_period.strftime("%B %Y"),
      current_total: current_total,
      mom_pct: mom_pct,
      yoy_pct: yoy_pct,
      top_service: top.fetch(:service_code),
      top_provider: top.fetch(:provider),
      top_amount: top_amount,
      top_share: top_share,
      fastest_service: fastest&.dig(:row, :service_code),
      fastest_provider: fastest&.dig(:row, :provider),
      fastest_pct: fastest&.fetch(:change),
      fastest_amount: fastest&.fetch(:amount)
    }
  end

  def percent_change(previous, current)
    return if previous.nil? || previous <= 0

    ((current - previous) / previous) * 100.0
  end
end
