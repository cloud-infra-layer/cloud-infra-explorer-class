require "rails_helper"

RSpec.describe "Searching stored resources", type: :feature do
  before do
    Resource.delete_all
    environment = Environment.create!(name: "Search journey", provider: "aws", region: "us-east-1")
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-web", name: "Web server", metadata: {})
    environment.resources.create!(provider: "aws", service: "s3", resource_id: "web-assets", name: "Web assets", metadata: {})
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  it "combines a search with a category and lets users clear search" do
    visit resources_path(category: "compute")
    fill_in "Search resources", with: "WEB"
    click_button "Search"
    expect(page).to have_field("Search resources", with: "WEB")
    expect(page).to have_css(".inventory-category.is-active", text: "Compute")
    within("tbody") do
      expect(page).to have_text("Web server")
      expect(page).not_to have_text("Web assets")
    end

    fill_in "Search resources", with: "missing"
    click_button "Search"
    expect(page).to have_text("No resources match the current filters.")
    expect(page).not_to have_css("table")

    click_link "Clear search"
    expect(page).to have_field("Search resources", with: "")
    expect(page).to have_css(".inventory-category.is-active", text: "Compute")
    expect(page).to have_css("tbody tr", count: 1)

    within(".inventory-categories") { click_link "Storage" }
    expect(page).to have_css("tbody tr", count: 2)
  end
end
