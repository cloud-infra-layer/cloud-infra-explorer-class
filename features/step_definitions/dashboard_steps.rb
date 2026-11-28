Given('the application has an empty resource inventory') do
  Resource.delete_all
end

Given('the application contains an EC2 instance named {string}') do |name|
  environment = Environment.find_or_create_by!(name: "Cucumber Testing") do |env|
    env.provider = "aws"
    env.region = "us-east-1"
  end

  Resource.create!(
    environment: environment,
    provider: "aws",
    service: "ec2",
    resource_id: "i-cucumber-001",
    name: name,
    region: "us-east-1",
    metadata: {
      instance_type: "t3.micro",
      state: "running"
    }
  )
end

Given('the application contains an S3 bucket named {string}') do |name|
  environment = Environment.find_or_create_by!(name: "Cucumber Testing") do |env|
    env.provider = "aws"
    env.region = "us-east-1"
  end

  Resource.create!(
    environment: environment,
    provider: "aws",
    service: "s3",
    resource_id: "cucumber-assets-bucket",
    name: name,
    region: "us-east-1",
    metadata: {
      creation_date: "2026-01-01T00:00:00Z",
      size_bytes: "1024",
      object_count: "3"
    }
  )
end

When('I visit the dashboard') do
  visit root_path
end

Then('I should see the cloud infrastructure dashboard') do
  expect(page).to have_css("a.category-card", text: "Compute")
  expect(page).to have_title(/Overview/)
end

Then('I should see the EC2 and S3 resource categories') do
  expect(page).to have_css("a.category-card[href='#{resources_path(category: 'compute')}']", text: "Compute")
  expect(page).to have_css("a.category-card[href='#{resources_path(category: 'storage')}']", text: "Storage")
  expect(page).to have_css("a.category-card[href='#{resources_path(category: 'databases')}']", text: "Database")
  expect(page).to have_css("a.category-card[href='#{resources_path(category: 'ai')}']", text: "AI / ML")
end

Then('I should see one resource in each category') do
  within("a.category-card[href='#{resources_path(category: 'compute')}']") do
    expect(page).to have_css(".resource-count", text: "1 resource")
  end
  within("a.category-card[href='#{resources_path(category: 'storage')}']") do
    expect(page).to have_css(".resource-count", text: "1 resource")
  end
end

Then("I should see category insights on the overview cards") do
  within("a.category-card[href='#{resources_path(category: 'compute')}']") do
    expect(page).to have_css(".category-icon")
    expect(page).to have_css(".category-insight", text: /running/)
  end
  within("a.category-card[href='#{resources_path(category: 'storage')}']") do
    expect(page).to have_css(".category-insight", text: /bucket/)
  end
end

Then('I should see {string}') do |text|
  expect(page).to have_content(text)
end

When('I click the EC2 category') do
  find('a.category-card[href="/resources?category=compute"]').click
end

When('I click the S3 category') do
  find('a.category-card[href="/resources?category=storage"]').click
end

When('I click {string}') do |label|
  click_link label
end

Then('I should not see {string}') do |text|
  expect(page).not_to have_content(text)
end

When("I visit the resource inventory") do
  visit resources_path
end
