
Before("@personalization") do
  @previous_personalization_settings = {
    "ENABLE_RESOURCE_PERSONALIZATION" => ENV["ENABLE_RESOURCE_PERSONALIZATION"]
  }

  ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
end

After("@personalization") do
  @previous_personalization_settings.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end

When('I pin the resource {string}') do |name|
  within("tbody tr", text: name) do
    find("button[aria-label^='Pin ']").click
  end
end

When('I unpin the resource {string}') do |name|
  within("tbody tr", text: name) do
    find("button[aria-label^='Unpin ']").click
  end
end

When('I hide the resource {string}') do |name|
  within("tbody tr", text: name) do
    find("button[aria-label^='Hide ']").click
  end
end

When('I restore the resource {string}') do |name|
  within("tbody tr", text: name) do
    find("button[aria-label^='Show ']").click
  end
end

Then('I should see a pinned row for {string}') do |name|
  expect(page).to have_css("tr.resource-row--pinned", text: name)
end

Then('I should not see a pinned row for {string}') do |name|
  expect(page).not_to have_css("tr.resource-row--pinned", text: name)
end

Then('I should see a hidden row for {string}') do |name|
  expect(page).to have_css("tr.resource-row--hidden", text: name)
end

Then('I should not see a hidden row for {string}') do |name|
  expect(page).not_to have_css("tr.resource-row--hidden", text: name)
end
