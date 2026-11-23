When("I visit the resource listing") do
  visit resources_path
end

When("I search for {string}") do |query|
  fill_in "Search resources", with: query
  click_button "Search"
end

When("I filter by {string}") do |category|
  select category, from: "Category"
  click_button "Search"
end

Then("the resource results should include {string}") do |name|
  expect(page).to have_css("table.resource-table tbody th[scope='row']", exact_text: name)
end

Then("the resource results should not include {string}") do |name|
  expect(page).not_to have_css("table.resource-table tbody th[scope='row']", exact_text: name)
end

Then("the resource results should be empty") do
  expect(page).to have_css("section[aria-labelledby='resources-heading']")
  expect(page).not_to have_css("table.resource-table tbody tr")
end

Then("the search query should be empty") do
  expect(page).to have_field("Search resources", with: "")
end

Then("the selected category should be {string}") do |category|
  expect(page).to have_select("Category", selected: category)
end
