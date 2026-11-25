require "rails_helper"

RSpec.describe "Managing the shared inventory", type: :feature do
  around do |example|
    original = ENV["ENABLE_RESOURCE_PERSONALIZATION"]
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    example.run
  ensure
    original.nil? ? ENV.delete("ENABLE_RESOURCE_PERSONALIZATION") : ENV["ENABLE_RESOURCE_PERSONALIZATION"] = original
  end

  before do
    environment = Environment.create!(name: "Shared inventory journey", provider: "aws", region: "us-east-1")
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-team-web",
      name: "Team web server", metadata: {})
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-team-db",
      name: "Team database", metadata: {}, hidden: true)
    environment.resources.create!(provider: "aws", service: "s3", resource_id: "team-assets",
      name: "Team assets", metadata: {})
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  def click_action(prefix, name)
    find("button[aria-label='#{prefix} #{name}']").click
  end

  it "pins, hides, restores, and unpins while retaining search and category chips" do
    visit resources_path(category: "compute", q: "team")

    expect(page).to have_css(".inventory-category.is-active", text: "Compute")
    expect(page).to have_css("tbody", text: "Team web server")
    expect(page).not_to have_css("tbody", text: "Team assets")
    click_action("Pin", "Team web server")
    expect(page).to have_css('[role="status"]', text: "Resource pinned for the team.")
    expect(page).to have_field("Search resources", with: "team")
    expect(page).to have_css("tr.resource-row--pinned", text: "Team web server")

    fill_in "Search resources", with: "web"
    click_button "Search"
    expect(page).to have_css(".inventory-category.is-active", text: "Compute")

    click_action("Hide", "Team web server")
    expect(page).to have_css('[role="status"]', text: "Resource hidden")
    expect(page).to have_css("tr.resource-row--hidden", text: "Team web server")

    click_action("Show", "Team web server")
    expect(page).to have_css('[role="status"]', text: "Resource restored")
    expect(page).not_to have_css("tr.resource-row--hidden", text: "Team web server")

    click_action("Unpin", "Team web server")
    expect(page).to have_css('[role="status"]', text: "Resource unpinned")
    expect(page).not_to have_css("tr.resource-row--pinned", text: "Team web server")
  end

  it "lets users multi-select categories from the inventory chips" do
    visit resources_path
    click_link "Compute"
    expect(page).to have_current_path(resources_path(category: "compute"))
    expect(page).to have_css("tbody", text: "Team web server")
    expect(page).not_to have_css("tbody", text: "Team assets")

    click_link "Storage"
    expect(page).to have_css("tbody", text: "Team web server")
    expect(page).to have_css("tbody", text: "Team assets")
    expect(page).to have_css(".inventory-category.is-active", text: "Compute")
    expect(page).to have_css(".inventory-category.is-active", text: "Storage")
  end

  it "keeps inventory readable while personalization writes are disabled" do
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "false"
    visit resources_path

    expect(page).to have_text("Pinning, hiding, and restoring are currently unavailable.")
    expect(page).to have_text("Team web server")
    expect(page).to have_css("tr.resource-row--hidden", text: "Team database")
    expect(page).not_to have_css(".resource-actions")
  end
end
