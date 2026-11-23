require "rails_helper"

RSpec.describe "Managing the shared inventory", type: :feature do
  around do |example|
    settings = {
      "ENABLE_RESOURCE_PERSONALIZATION" => "true",
      "RESOURCE_ADMIN_USERNAME" => "test-editor",
      "RESOURCE_ADMIN_PASSWORD" => "test-password"
    }
    original = ENV.to_h.slice(*settings.keys)
    ENV.update(settings)
    example.run
  ensure
    settings.each_key { |key| ENV[key] = original[key] }
  end

  before do
    environment = Environment.create!(name: "Shared inventory journey", provider: "aws", region: "us-east-1")
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-team-web",
      name: "Team web server", metadata: {})
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-team-db",
      name: "Team database", metadata: {}, hidden: true)
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  it "pins, hides, restores, and unpins while retaining search and category context" do
    page.driver.header("Authorization", ActionController::HttpAuthentication::Basic.encode_credentials("test-editor", "test-password"))
    visit resources_path(service: "ec2", q: "team")

    expect(page).to have_css("tbody", text: "Unpinned")
    find_button("Pin", exact: true).click
    expect(page).to have_css('[role="status"]', text: "Resource pinned for the team.")
    expect(page).to have_field("Search resources", with: "team")
    expect(page).to have_select("Category", selected: "EC2")

    click_link "Pinned resources"
    expect(page).to have_css("tbody", text: "Team web server")
    fill_in "Search resources", with: "web"
    click_button "Search"
    expect(page).to have_css('.inventory-views a[aria-current="page"]', text: "Pinned resources")
    expect(page).to have_select("Category", selected: "EC2")

    find_button("Hide", exact: true).click
    expect(page).to have_css('[role="status"]', text: "Resource hidden")
    expect(page).to have_text("No resources match your search")
    expect(page).to have_field("Search resources", with: "web")
    visit current_url
    expect(page).not_to have_css("tbody", text: "Team web server")

    click_link "Hidden resources"
    expect(page).to have_css("tbody", text: "Team web server")
    expect(page).to have_css("tbody", text: "Hidden")
    expect(page).not_to have_css("tbody", text: "Team database")
    click_link "Clear search"
    expect(page).to have_css("tbody", text: "Team database")
    fill_in "Search resources", with: "web"
    click_button "Search"
    expect(page).to have_css('.inventory-views a[aria-current="page"]', text: "Hidden resources")
    expect(page).to have_select("Category", selected: "EC2")
    expect(page).not_to have_css("tbody", text: "Team database")

    find_button("Restore", exact: true).click
    expect(page).to have_css('[role="status"]', text: "Resource restored")
    expect(page).to have_css('.inventory-views a[aria-current="page"]', text: "Hidden resources")
    expect(page).not_to have_css("tbody", text: "Team web server")
    click_link "Pinned resources"
    expect(page).to have_css("tbody", text: "Team web server")
    find_button("Unpin", exact: true).click
    expect(page).to have_css('[role="status"]', text: "Resource unpinned")
    expect(page).not_to have_css("tbody", text: "Team web server")

    click_link "All visible resources"
    visit current_url
    expect(page).to have_css("tbody", text: "Unpinned")
    expect(page).to have_field("Search resources", with: "web")
    expect(page).to have_select("Category", selected: "EC2")
  end

  it "shows empty pinned and hidden views and retains the view when switching categories" do
    visit root_path
    click_link "Pinned"
    expect(page).to have_text("No pinned resources")
    click_link "Hidden resources"
    expect(page).to have_css("tbody", text: "Team database")
    click_link "S3 Resources"
    expect(page).to have_text("No hidden resources")
    expect(page).to have_css('.inventory-views a[aria-current="page"]', text: "Hidden resources")
  end

  it "keeps inventory readable while personalization writes are disabled" do
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "false"
    visit resources_path

    expect(page).to have_text("Pinning, hiding, and restoring are currently unavailable.")
    expect(page).to have_text("Team web server")
    expect(page).not_to have_css(".resource-actions")
    click_link "Hidden resources"
    expect(page).to have_text("Team database")
    expect(page).not_to have_css(".resource-actions")
  end
end
