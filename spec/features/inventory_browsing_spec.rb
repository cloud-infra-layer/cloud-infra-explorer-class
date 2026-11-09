require "rails_helper"

RSpec.describe "Browsing stored inventory", type: :feature do
  let(:environment) { Environment.create!(name: "Course development", provider: "aws", region: "us-east-1") }
  let(:other_environment) { Environment.create!(name: "Course testing", provider: "aws", region: "us-east-1") }
  let(:instance_attributes) do
    {
      provider: "aws", service: "ec2", resource_id: "i-course-web",
      name: "Course web server", region: "us-east-1",
      metadata: { instance_type: "t3.micro", state: "running" }
    }
  end
  let(:bucket_attributes) do
    {
      provider: "aws", service: "s3", resource_id: "course-assets",
      name: "Course assets", region: nil, metadata: {}
    }
  end

  before do
    # Minitest fixtures or seeds may already exist in the shared test database.
    # This deletion rolls back with the example's transaction.
    Resource.delete_all

    # Browsing stored inventory must not initiate discovery.
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  it "shows the same cloud identifier separately for each environment" do
    first = environment.resources.create!(instance_attributes)
    second = other_environment.resources.create!(instance_attributes)
    environment.resources.create!(bucket_attributes)

    visit root_path

    within("#ec2-resources") do
      expect(page).to have_css(".resource-count", text: "2 resources")
      expect(page).to have_css("tbody tr", count: 2)
      [ first, second ].each do |resource|
        within("#resource-#{resource.id}") do
          expect(page).to have_text(resource.environment.name)
          expect(page).to have_text(resource.resource_id)
        end
      end
    end
    within("#s3-resources") do
      expect(page).to have_css(".resource-count", text: "1 resource")
      expect(page).to have_text("Course assets")
      expect(page).to have_text("Not specified")
    end
    within("a.category-card", text: "EC2 Instances") do
      expect(page).to have_css(".resource-count", text: "2 resources")
    end
    within("a.category-card", text: "S3 Buckets") do
      expect(page).to have_css(".resource-count", text: "1 resource")
    end
  end

  it "lets a user follow category cards, switch categories, and return to the dashboard" do
    environment.resources.create!(instance_attributes)
    environment.resources.create!(bucket_attributes)

    visit root_path
    within(".category-grid") { click_link "EC2 Instances" }

    expect(page).to have_current_path(resources_path(service: "ec2"))
    expect(page).to have_css("h1", text: "EC2 Resources")
    within("table.resource-table") do
      expect(page).to have_css("tbody tr", count: 1)
      expect(page).to have_text("Course web server")
      expect(page).to have_text("Instance type: t3.micro · State: running")
      expect(page).not_to have_text("Course assets")
    end

    within("nav[aria-label='Primary navigation']") { click_link "S3 Resources" }

    expect(page).to have_current_path(resources_path(service: "s3"))
    within("table.resource-table") do
      expect(page).to have_css("tbody tr", count: 1)
      expect(page).to have_text("Course assets")
      expect(page).to have_text("Unknown")
      expect(page).to have_text("No metadata available")
      expect(page).not_to have_text("Course web server")
    end

    click_link "Back to dashboard"
    expect(page).to have_current_path(root_path)
    within(".category-grid") { click_link "S3 Buckets" }
    expect(page).to have_css("h1", text: "S3 Resources")
  end

  it "keeps an empty category accessible beside populated inventory" do
    environment.resources.create!(instance_attributes)

    visit root_path

    expect(page).to have_css("#ec2-resources tbody tr", count: 1)
    within("#s3-resources") do
      expect(page).to have_text("No S3 buckets stored yet.")
      expect(page).to have_css(".resource-count", text: "0 resources")
      expect(page).not_to have_css("table")
    end
    within("a.category-card", text: "S3 Buckets") do
      expect(page).to have_text("0 resources")
    end
    within(".category-grid") { click_link "S3 Buckets" }
    expect(page).to have_text("No S3 resources found.")
    expect(page).not_to have_css("table")
  end

  it "guides users through an entirely empty inventory" do
    visit root_path

    expect(page).to have_css(".category-card .resource-count", text: "0 resources", count: 2)
    expect(page).to have_text("No EC2 instances stored yet.")
    expect(page).to have_text("No S3 buckets stored yet.")
    expect(page).not_to have_css("table")

    within(".category-grid") { click_link "EC2 Instances" }
    expect(page).to have_text("No EC2 resources found.")
    expect(page).not_to have_css("table")

    visit resources_path
    expect(page).to have_text("No resources found.")
    expect(page).not_to have_css("table")
  end

  it "reflects successful synthetic syncs without duplicating repeated inventory" do
    sync = ResourceSync.new(environment: environment)
    sync.call(resources: [ instance_attributes ])
    visit root_path
    expect(page).to have_text("Course web server")

    updated = instance_attributes.merge(name: "Renamed web server")
    sync.call(resources: [ updated, bucket_attributes ])
    sync.call(resources: [ updated, bucket_attributes ])
    visit root_path

    within("#ec2-resources") do
      expect(page).to have_text("Renamed web server")
      expect(page).not_to have_text("Course web server")
      expect(page).to have_css("tbody tr", count: 1)
      expect(page).to have_css(".resource-count", text: "1 resource")
    end
    within("#s3-resources") do
      expect(page).to have_text("Course assets")
      expect(page).to have_css("tbody tr", count: 1)
    end
  end

  it "continues to display the previous inventory after a rejected sync batch" do
    sync = ResourceSync.new(environment: environment)
    sync.call(resources: [ instance_attributes ])

    expect do
      sync.call(resources: [
        instance_attributes.merge(name: "Uncommitted rename"),
        bucket_attributes.merge(service: "unsupported")
      ])
    end.to raise_error(ResourceSync::Error) { |error| expect(error.code).to eq("invalid_resource") }

    visit root_path

    expect(page).to have_text("Course web server")
    expect(page).not_to have_text("Uncommitted rename")
    expect(page).not_to have_text("Course assets")
    expect(page).to have_css("#ec2-resources tbody tr", count: 1)
    expect(page).to have_text("No S3 buckets stored yet.")
  end
end
