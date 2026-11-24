
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
