require "rails_helper"

RSpec.describe "Inventory visibility and ordering", type: :request do
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

  it "defaults missing or blank visibility to visible, with pins before alphabetical names" do
    create_resource("i-ordinary", name: "Alpha")
    create_resource("i-pin", name: "Zebra", pinned: true)
    create_resource("i-hidden", name: "Hidden", hidden: true, pinned: true)

    [ nil, "", "   ", "visible" ].each do |visibility|
      get resources_path, params: { visibility: visibility }
      expect(response).to have_http_status(:ok)
      expect(listed_names).to eq([ "Zebra", "Alpha" ])
    end
  end

  it "combines hidden visibility with search and service filters and orders hidden pins first" do
    create_resource("i-visible", name: "Web visible")
    create_resource("i-hidden", name: "Web alpha", hidden: true)
    create_resource("i-hidden-pin", name: "Web zebra", hidden: true, pinned: true)
    create_resource("i-other", name: "Worker", hidden: true)
    create_resource("web-bucket", name: "Web bucket", service: "s3", hidden: true)

    get resources_path, params: { visibility: "hidden", service: "ec2", q: "WEB" }

    expect(response).to have_http_status(:ok)
    expect(listed_names).to eq([ "Web zebra", "Web alpha" ])
    expect(Resource.count).to eq(5)
  end

  [ "all", "HIDDEN", [ "hidden" ], { value: "hidden" } ].each do |visibility|
    it "rejects invalid visibility #{visibility.inspect}" do
      get resources_path, params: { visibility: visibility }
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "keeps identical AWS IDs from different environments separate" do
    first = create_resource("i-shared")
    other = Environment.create!(name: "Other visibility environment", provider: "aws", region: "us-east-1")
    second = first.dup
    second.assign_attributes(environment: other, hidden: true, name: "Other hidden server")
    second.save!

    get resources_path
    expect(listed_names).to eq([ first.name ])
    get resources_path, params: { visibility: "hidden" }
    expect(listed_names).to eq([ second.name ])
  end

  it "uses visible inventory for dashboard ordering, tables, and card counts on both routes" do
    ordinary = create_resource("i-ordinary", name: "Alpha")
    pinned = create_resource("i-pinned", name: "Zebra", pinned: true)
    create_resource("i-hidden", hidden: true, pinned: true)
    create_resource("hidden-bucket", service: "s3", hidden: true)

    [ root_path, dashboard_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.css("#ec2-resources tbody tr").map { |row| row["id"] }).to eq([ "resource-#{pinned.id}", "resource-#{ordinary.id}" ])
      expect(document.at_css("#ec2-resources .resource-count").text.strip).to eq("2 resources")
      expect(document.at_css("#s3-resources .resource-count").text.strip).to eq("0 resources")
      expect(document.css("#s3-resources table")).to be_empty
      expect(document.css(".category-card .resource-count").map { |node| node.text.strip }).to eq([ "2 resources", "0 resources" ])
    end
  end

  it "renders empty visible inventory when all stored resources are hidden without deleting them" do
    create_resource("i-hidden", hidden: true)
    create_resource("hidden-bucket", service: "s3", hidden: true)

    get dashboard_path
    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.css("main table")).to be_empty
    expect(document.css(".category-card .resource-count").map { |node| node.text.strip }).to eq([ "0 resources", "0 resources" ])

    get resources_path
    expect(listed_names).to be_empty
    get resources_path, params: { visibility: "hidden" }
    expect(listed_names.size).to eq(2)
    expect(Resource.count).to eq(2)
  end
end
