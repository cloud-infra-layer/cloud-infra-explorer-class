require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "homepage and dashboard route render overview categories" do
    [ root_url, dashboard_url ].each do |url|
      get url

      assert_response :success
      assert_select "title", text: /Overview/
      assert_select ".connected-account-card", count: 1
      assert_category_card "compute", "Compute", 1
      assert_category_card "storage", "Storage", 1
      assert_category_card "databases", "Database", 0
      assert_category_card "ai", "AI / ML", 0
    end
  end

  test "dashboard cards show stored resource counts without inline tables" do
    get dashboard_url

    assert_response :success
    assert_category_card "compute", "Compute", 1
    assert_category_card "storage", "Storage", 1
    assert_select ".category-grid table", count: 0
  end

  test "dashboard counts repeated AWS identifiers in separate environments" do
    original = resources(:web_server)
    second = original.dup
    second.environment = environments(:course_testing)
    second.save!

    get dashboard_url

    assert_response :success
    assert_category_card "compute", "Compute", 2
    assert_category_card "storage", "Storage", 1
  end

  test "empty storage category remains visible alongside compute" do
    Resource.where(service: "s3").delete_all

    get dashboard_url

    assert_response :success
    assert_category_card "storage", "Storage", 0
    assert_category_card "compute", "Compute", 1
    assert_select ".category-card .category-insight", text: "No stored resources yet.", count: 3
  end

  test "empty inventory renders zero-count category cards" do
    Resource.delete_all

    get root_url

    assert_response :success
    Resource::CATEGORIES.each_key do |category|
      assert_category_card category, Resource::CATEGORIES.fetch(category).fetch(:label), 0
    end
    assert_select ".category-card .category-insight", text: "No stored resources yet.", count: 4
    assert_select ".category-grid table", count: 0
  end

  test "resource names are escaped on the resource listing instead of the dashboard" do
    resource = resources(:web_server)
    resource.update!(name: "<script>alert('example')</script>")

    get resources_path(service: "ec2")

    assert_response :success
    assert_select "main script", count: 0
    assert_select "tbody th", text: resource.name
  end

  test "dashboard shows linked category cards with stored counts" do
    get root_url

    assert_response :success
    assert_select ".category-card", count: 4
    assert_category_card "compute", "Compute", Resource.where(provider: "aws", service: "ec2").visible.count
    assert_category_card "storage", "Storage", Resource.where(provider: "aws", service: "s3").visible.count
  end

  test "dashboard reflects changes to stored inventory" do
    resource = resources(:web_server).dup
    resource.resource_id = "i-dashboard-test"
    resource.save!

    get root_url

    assert_response :success
    assert_category_card "compute", "Compute", Resource.where(provider: "aws", service: "ec2").visible.count
    assert_category_card "storage", "Storage", Resource.where(provider: "aws", service: "s3").visible.count
  end

  test "empty category stays visible alongside populated category" do
    Resource.where(service: "ec2").delete_all

    get root_url

    assert_response :success
    assert_category_card "compute", "Compute", 0
    assert_category_card "storage", "Storage", Resource.where(provider: "aws", service: "s3").count
    assert_select ".category-card .category-insight", text: "No stored resources yet.", count: 3
  end

  test "dashboard renders without AWS credentials" do
    credential_keys = %w[
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN
      AWS_PROFILE
      AWS_SHARED_CREDENTIALS_FILE
      AWS_CONFIG_FILE
    ]

    original_values = credential_keys.to_h do |key|
      [ key, ENV.delete(key) ]
    end

    get root_url

    assert_response :success
    assert_select ".category-card", count: 4
  ensure
    original_values&.each do |key, value|
      ENV[key] = value
    end
  end

  test "dashboard shows cost insights when monthly snapshots exist" do
    environment = environments(:course_development)
    CostSnapshot.delete_all
    [
      [ Date.new(2026, 10, 1), Date.new(2026, 10, 31), "Amazon Elastic Compute Cloud - Compute", "20.00" ],
      [ Date.new(2026, 10, 1), Date.new(2026, 10, 31), "Amazon Bedrock", "40.00" ],
      [ Date.new(2026, 11, 1), Date.new(2026, 11, 30), "Amazon Elastic Compute Cloud - Compute", "25.00" ],
      [ Date.new(2026, 11, 1), Date.new(2026, 11, 30), "Amazon Bedrock", "50.00" ]
    ].each do |period_start, period_end, service_code, amount|
      environment.cost_snapshots.create!(
        period_start: period_start,
        period_end: period_end,
        granularity: "MONTHLY",
        service_code: service_code,
        amount: amount,
        currency: "USD"
      )
    end

    get dashboard_url

    assert_response :success
    assert_select ".cost-insights-period", "November 2026"
    assert_select ".dashboard-stats .stat-card", count: 3
    assert_select ".stat-card:nth-child(1) .stat-label", "Monthly spend"
    assert_select ".stat-card:nth-child(1) .stat-value span", "$75.00"
    assert_select ".stat-card:nth-child(1) .stat-delta", text: /MoM/
    assert_select ".stat-card:nth-child(1) .stat-trend--up", "+25.0%"
    assert_select ".stat-card:nth-child(2) .stat-value span", "AWS Bedrock"
    assert_select ".cost-chart-point", count: 4
    assert_select ".cost-chart-range.is-active", "6M"
    assert_select ".cost-chart-legend", text: /AWS Bedrock/
  end

  test "cost explorer uses the selected environment and ignores sibling environment spend" do
    CostSnapshot.delete_all
    selected = environments(:course_development)
    other = environments(:course_testing)

    selected.cost_snapshots.create!(
      period_start: Date.new(2026, 11, 1),
      period_end: Date.new(2026, 11, 30),
      granularity: "MONTHLY",
      service_code: "Amazon Bedrock",
      amount: "50.00",
      currency: "USD"
    )
    other.cost_snapshots.create!(
      period_start: Date.new(2026, 11, 1),
      period_end: Date.new(2026, 11, 30),
      granularity: "MONTHLY",
      service_code: "Amazon Bedrock",
      amount: "999.00",
      currency: "USD"
    )

    get dashboard_url, params: { environment_id: selected.id }

    assert_response :success
    assert_select ".stat-card:nth-child(1) .stat-value span", "$50.00"
    assert_select ".stat-card:nth-child(1) .stat-value span", text: "$1049.00", count: 0

    get dashboard_url, params: { environment_id: other.id }

    assert_response :success
    assert_select ".stat-card:nth-child(1) .stat-value span", "$999.00"
  end

  private

  def assert_category_card(category, name, count)
    assert_select "a.category-card[href=?]",
      resources_path(category: category),
      count: 1 do
      assert_select "h2", name
      assert_select ".resource-count",
        "#{count} #{count == 1 ? 'resource' : 'resources'}"
    end
  end
end
