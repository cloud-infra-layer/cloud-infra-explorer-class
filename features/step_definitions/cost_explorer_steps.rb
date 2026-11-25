Given("the application contains monthly cost snapshots for the demo environment") do
  environment = Environment.find_or_create_by!(name: "Cucumber Testing") do |env|
    env.provider = "aws"
    env.region = "us-east-1"
  end

  CostSnapshot.where(environment: environment).delete_all

  [
    [ Date.new(2025, 11, 1), Date.new(2025, 11, 30), "Amazon Elastic Compute Cloud - Compute", "20.00" ],
    [ Date.new(2025, 11, 1), Date.new(2025, 11, 30), "Amazon Bedrock", "30.00" ],
    [ Date.new(2026, 10, 1), Date.new(2026, 10, 31), "Amazon Elastic Compute Cloud - Compute", "22.00" ],
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

Then("I should see the cost insights for {string}") do |period|
  expect(page).to have_css(".cost-insights-period", text: period)
end

Then("I should see the Cost Explorer chart") do
  expect(page).to have_css("#cost-overview-heading", text: "Cost Explorer")
  expect(page).to have_css(".cost-chart-point")
end

Then("the cost chart legend should include {string}") do |label|
  expect(page).to have_css(".cost-chart-legend", text: label)
end

Then("the cost chart range {string} should not be available") do |label|
  expect(page).not_to have_css(".cost-chart-range", text: label)
end

Then("the active cost chart range should be {string}") do |label|
  expect(page).to have_css(".cost-chart-range.is-active", text: label)
end

When("I choose the cost chart range {string}") do |label|
  within(".cost-chart-ranges") { click_link label }
end
