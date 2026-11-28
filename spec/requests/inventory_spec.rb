require "rails_helper"

RSpec.describe "Inventory HTTP responses", type: :request do
  before do
    # Isolate page-wide assertions from existing test data. Rolled back per example.
    Resource.delete_all
  end

  let(:environment) { Environment.create!(name: "Request examples", provider: "aws", region: "us-east-1") }
  let(:instance) do
    environment.resources.create!(
      provider: "aws", service: "ec2", resource_id: "i-request-web",
      name: "Request web server", region: "us-east-1", metadata: {}
    )
  end

  [ "/", "/dashboard" ].each do |path|
    it "serves the empty dashboard at #{path}" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("title").text).to include("Overview")
      expect(document.css("main h1")).to be_empty
      expect(document.css("main .category-card .category-insight").map { |node| node.text.strip }).to eq([ "No stored resources yet." ] * 4)
      expect(document.css("main table")).to be_empty
    end
  end

  [ "lambda", "EC2", [ "ec2" ], { name: "s3" } ].each do |service|
    it "returns 404 for service filter #{service.inspect}" do
      get resources_path, params: { service: service }

      expect(response).to have_http_status(:not_found)
    end
  end

  [ nil, "" ].each do |service|
    it "lists both categories across environments for filter #{service.inspect}" do
      instance
      other = Environment.create!(name: "Another environment", provider: "aws", region: "us-west-2")
      other.resources.create!(provider: "aws", service: "s3", resource_id: "request-assets", name: "Request assets", metadata: {})

      get resources_path, params: { service: service }

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.css("main h1")).to be_empty
      expect(document.css("tbody tr").size).to eq(2)
      expect(document.css("tbody th").map(&:text)).to contain_exactly("Request web server", "Request assets")
      expect(document.css("thead th").map(&:text)).to include("Provider")
      expect(document.css("thead th").map(&:text)).not_to include("Status")
    end
  end

  it "escapes stored environment fields on the dashboard and resource fields in listings" do
    html = "<script>alert('inventory')</script>"
    instance.update!(name: html, resource_id: html, region: html)
    environment.update!(name: html)

    get dashboard_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css("main script")).to be_empty
    expect(document.at_css(".connected-account-card h2").text).to eq(html)
    expect(response.body).to include("&lt;script&gt;")

    get resources_path, params: { service: "ec2" }
    expect(response).to have_http_status(:ok)
    listing = Nokogiri::HTML(response.body)
    expect(listing.css("tbody script")).to be_empty
    expect(listing.at_css("tbody th").text).to eq(html)
    expect(response.body).to include("&lt;script&gt;")
  end

  it "escapes stored resource fields and metadata in category listings" do
    html = "<script>alert('inventory')</script>"
    instance.update!(name: html, resource_id: html, region: html, metadata: { state: html })

    get resources_path, params: { service: "ec2" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css("tbody script")).to be_empty
    expect(document.at_css("tbody th").text).to eq(html)
    cells = document.css("tbody td").map { |node| node.text.gsub(/\s+/, " ").strip }
    expect(cells[0, 4]).to eq([ "Compute", "AWS", "EC2", html ])
    expect(document.css(".resource-details-list dd").map(&:text)).to include(html)
    expect(document.css("thead th").map(&:text)).to include("Metadata")
    expect(document.css("thead th").map(&:text)).not_to include("ID")
    expect(document.css("thead th").map(&:text)).not_to include("Details")
    expect(response.body).to include("&lt;script&gt;")
  end
end
