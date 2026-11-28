require "rails_helper"

RSpec.describe "Cost Explorer on the overview", type: :feature do
  let!(:environment) { Environment.create!(name: "AWS Sandbox", provider: "aws", region: "us-east-1") }

  before do
    Resource.delete_all
    CostSnapshot.delete_all
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)

    [
      [ Date.new(2025, 11, 1), Date.new(2025, 11, 30), "Amazon Elastic Compute Cloud - Compute", "18.00" ],
      [ Date.new(2025, 11, 1), Date.new(2025, 11, 30), "Amazon Bedrock", "28.00" ],
      [ Date.new(2026, 9, 1), Date.new(2026, 9, 30), "Amazon Elastic Compute Cloud - Compute", "21.00" ],
      [ Date.new(2026, 9, 1), Date.new(2026, 9, 30), "Amazon Bedrock", "35.00" ],
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
  end

  it "shows period-scoped spend insights and lets users change chart ranges" do
    visit root_path

    expect(page).to have_css(".cost-insights-period", text: "November 2026")
    expect(page).to have_css(".stat-card", text: "Monthly spend")
    expect(page).to have_css(".stat-delta-label", text: "MoM")
    expect(page).to have_css(".stat-delta-label", text: "YoY")
    expect(page).to have_css(".cost-chart-legend", text: "AWS Bedrock")
    expect(page).to have_css(".cost-chart-range.is-active", text: "6M")
    expect(page).not_to have_css(".cost-chart-range", text: "1M")
    expect(page).to have_css(".connected-account-card .account-region", text: /AWS ·/)

    within(".cost-chart-ranges") { click_link "3M" }
    expect(page).to have_current_path(root_path(cost_range: "3M"), ignore_query: false)
    expect(page.current_url).to include("#cost-explorer")
    expect(page).to have_css(".cost-chart-range.is-active", text: "3M")
    expect(page).to have_css(".cost-chart-point")

    within(".cost-chart-ranges") { click_link "Max" }
    expect(page).to have_current_path(root_path(cost_range: "MAX"), ignore_query: false)
    expect(page.current_url).to include("#cost-explorer")
    expect(page).to have_css(".cost-chart-range.is-active", text: "Max")
  end

  it "scopes spend insights to the selected environment" do
    sibling = Environment.create!(name: "Sibling Sandbox", provider: "aws", region: "us-west-2")
    sibling.cost_snapshots.create!(
      period_start: Date.new(2026, 11, 1),
      period_end: Date.new(2026, 11, 30),
      granularity: "MONTHLY",
      service_code: "Amazon Simple Storage Service",
      amount: "12.00",
      currency: "USD"
    )

    visit root_path(environment_id: environment.id)
    within(".stat-card", text: "Monthly spend") do
      expect(page).to have_css(".stat-value", text: "$75.00")
    end

    visit root_path(environment_id: sibling.id)
    within(".stat-card", text: "Monthly spend") do
      expect(page).to have_css(".stat-value", text: "$12.00")
    end
  end
end
