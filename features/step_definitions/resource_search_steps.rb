When("I visit the resource listing") do
  visit resources_path
end

When("I search for {string}") do |query|
  fill_in "Search resources", with: query
  click_button "Search"
end

When("I filter by {string}") do |category|
  mapping = {
    "Compute" => "compute",
    "Storage" => "storage",
    "Database" => "databases",
    "AI / ML" => "ai"
  }

  if category == "All categories"
    query = find_field("Search resources").value
    visit resources_path(q: query.presence)
  else
    key = mapping.fetch(category)
    within(".inventory-categories") { click_link category }
    expect(page).to have_current_path(%r{/resources\?.*category=#{key}}, ignore_query: false)
  end
end

Then("the resource results should include {string}") do |name|
  expect(page).to have_css("table.resource-table tbody th[scope='row']", exact_text: name)
end

Then("the resource results should not include {string}") do |name|
  expect(page).not_to have_css("table.resource-table tbody th[scope='row']", exact_text: name)
end

Then("the resource results should be empty") do
  expect(page).to have_css("section[aria-label='Resource inventory']")
  expect(page).not_to have_css("table.resource-table tbody tr")
end

Then("the search query should be empty") do
  expect(page).to have_field("Search resources", with: "")
end

Then("the Compute category filter should be active") do
  expect(page).to have_css(".inventory-category.is-active", text: "Compute")
end

When("I add the Storage category filter") do
  within(".inventory-categories") { click_link "Storage" }
end

Then("the inventory table should use a Metadata column") do
  expect(page).to have_css("thead th", text: "Metadata")
  expect(page).not_to have_css("thead th", text: "ID")
  expect(page).not_to have_css("thead th", text: "Details")
end

Then("the metadata for {string} should include resource ID {string}") do |name, resource_id|
  within("tbody tr", text: name) do
    expect(page).to have_css(".resource-details-list dd.resource-identifier", text: resource_id, visible: :all)
  end
end
