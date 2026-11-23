
Before("@personalization") do
  @previous_personalization_settings = {
    "ENABLE_RESOURCE_PERSONALIZATION" => ENV["ENABLE_RESOURCE_PERSONALIZATION"],
    "RESOURCE_ADMIN_USERNAME" => ENV["RESOURCE_ADMIN_USERNAME"],
    "RESOURCE_ADMIN_PASSWORD" => ENV["RESOURCE_ADMIN_PASSWORD"]
  }

  ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
  ENV["RESOURCE_ADMIN_USERNAME"] = "cucumber-admin"
  ENV["RESOURCE_ADMIN_PASSWORD"] = "cucumber-password"

  credentials = ActionController::HttpAuthentication::Basic.encode_credentials(
    "cucumber-admin", "cucumber-password"
  )

  page.driver.header("Authorization", credentials)
end

After("@personalization") do
  @previous_personalization_settings.each do |key, value|
    ENV[key] = value
  end

  page.driver.header("Authorization", nil)
end

When('I pin the resource {string}') do |name|
  within("tbody tr", text: name) do
    click_button "Pin"
  end
end

When('I unpin the resource {string}') do |name|
  within("tbody tr", text: name) do
    click_button "Unpin"
  end
end

When('I hide the resource {string}') do |name|
  within("tbody tr", text: name) do
    click_button "Hide"
  end
end

When('I restore the resource {string}') do |name|
  within("tbody tr", text: name) do
    click_button "Restore"
  end
end
