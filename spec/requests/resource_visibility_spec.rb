require "rails_helper"

RSpec.describe "Inventory category filtering and ordering", type: :request do
  let(:environment) { Environment.create!(name: "Visibility examples", provider: "aws", region: "us-east-1") }

  def create_resource(identifier, **attributes)
    environment.resources.create!(
      { provider: "aws", service: "ec2", resource_id: identifier,
        name: identifier, region: "us-east-1", metadata: {} }.merge(attributes)
    )
  end

  def listed_names
    Nokogiri::HTML(response.body).css("tbody th").map(&:text)
  end

  before do
    Resource.delete_all
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  it "defaults to all categories with pins before alphabetical names, including hidden rows" do
    create_resource("i-ordinary", name: "Alpha")
    create_resource("i-pin", name: "Zebra", pinned: true)
    create_resource("i-hidden", name: "Hidden", hidden: true, pinned: true)

    get resources_path
    expect(response).to have_http_status(:ok)
    expect(listed_names).to eq([ "Hidden", "Zebra", "Alpha" ])
    expect(response.body).to include('aria-pressed="true"')
  end

  it "narrows inventory by one or more categories while preserving search" do
    create_resource("i-visible", name: "Web visible")
    create_resource("i-hidden", name: "Web alpha", hidden: true)
    create_resource("web-bucket", name: "Web bucket", service: "s3", hidden: true)
    create_resource("i-other", name: "Worker")

    get resources_path, params: { category: "compute", q: "WEB" }
    expect(response).to have_http_status(:ok)
    expect(listed_names).to eq([ "Web alpha", "Web visible" ])

    get resources_path, params: { categories: %w[storage compute], q: "WEB" }
    expect(listed_names).to eq([ "Web alpha", "Web bucket", "Web visible" ])
  end

  it "rejects unknown categories" do
    get resources_path, params: { category: "lambda" }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps identical AWS IDs from different environments separate" do
    first = create_resource("i-shared")
    other = Environment.create!(name: "Other visibility environment", provider: "aws", region: "us-east-1")
    second = first.dup
    second.assign_attributes(environment: other, hidden: true, name: "Other hidden server")
    second.save!

    get resources_path
    expect(listed_names).to contain_exactly(first.name, second.name)
  end

  it "uses visible inventory for dashboard card counts on both routes" do
    create_resource("i-ordinary", name: "Alpha")
    create_resource("i-pinned", name: "Zebra", pinned: true)
    create_resource("i-hidden", hidden: true, pinned: true)
    create_resource("hidden-bucket", service: "s3", hidden: true)

    [ root_path, dashboard_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.css("a.category-card[href='#{resources_path(category: 'compute')}'] .resource-count").map { |node| node.text.strip }).to eq([ "2 resources" ])
      expect(document.css("a.category-card[href='#{resources_path(category: 'storage')}'] .resource-count").map { |node| node.text.strip }).to eq([ "0 resources" ])
    end
  end

  it "renders empty visible inventory when all stored resources are hidden without deleting them" do
    create_resource("i-hidden", hidden: true)
    create_resource("hidden-bucket", service: "s3", hidden: true)

    get dashboard_path
    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.css(".category-card .resource-count").map { |node| node.text.strip }).to eq([ "0 resources" ] * 4)

    get resources_path
    expect(listed_names.size).to eq(2)
    expect(Resource.count).to eq(2)
  end
end
