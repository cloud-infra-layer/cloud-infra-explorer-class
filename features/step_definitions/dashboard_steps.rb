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
      purpose: "Static assets"
    }
  )
end

When('I visit the dashboard') do
  visit root_path
end

Then('I should see the cloud infrastructure dashboard') do
  expect(page).to have_css("h1", text: "Cloud Infrastructure Explorer")
end

Then('I should see the EC2 and S3 resource categories') do
  expect(page).to have_css("a.category-card[href='#{resources_path(service: 'ec2')}']", text: "Compute")
  expect(page).to have_css("a.category-card[href='#{resources_path(service: 's3')}']", text: "Storage")
end

Then('I should see one resource in each category') do
  [ "ec2", "s3" ].each do |service|
    within("a.category-card[href='#{resources_path(service: service)}']") do
      expect(page).to have_css(".resource-count", text: "1 resource")
    end
  end
end

Then('I should see {string}') do |text|
  expect(page).to have_content(text)
end

When('I click the EC2 category') do
  find('a.category-card[href="/resources?service=ec2"]').click
end

When('I click the S3 category') do
  find('a.category-card[href="/resources?service=s3"]').click
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
