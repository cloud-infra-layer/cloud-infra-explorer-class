require "rails_helper"

RSpec.describe "Dashboard category summaries", type: :request do
  let(:environment) { Environment.create!(name: "Card examples", provider: "aws", region: "us-east-1") }

  def create_instance(identifier, **attributes)
    environment.resources.create!({
      provider: "aws", service: "ec2", resource_id: identifier, name: identifier,
      region: "us-east-1", metadata: { state: "running" }
    }.merge(attributes))
  end

  def compute_card
    Nokogiri::HTML(response.body).at_css("a.category-card[href='#{resources_path(category: 'compute')}']")
  end

  [ 0, 1, 2 ].each do |pins|
    it "retains the description and overview with #{pins} pinned resources" do
      2.times { |index| create_instance("i-card-#{index}", pinned: index < pins) }

      [ root_path, dashboard_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        card = compute_card
        expect(card.at_css(".resource-count").text).to eq("2 resources")
        expect(card.at_css(".category-insight").text).to eq("2 running · 0 stopped")
        expect(card.at_css(".category-description").text).to eq("Virtual machines and instance capacity.")
        expect(card.css(".category-pinned").map(&:text)).to eq(pins.zero? ? [] : [ "#{pins} Pinned" ])
      end
    end
  end

  it "excludes hidden pins from the overview and pinned count" do
    create_instance("i-visible", pinned: true)
    create_instance("i-hidden", pinned: true, hidden: true)

    get root_path

    expect(compute_card.at_css(".resource-count").text).to eq("1 resource")
    expect(compute_card.at_css(".category-insight").text).to eq("1 running · 0 stopped")
    expect(compute_card.at_css(".category-pinned").text).to eq("1 Pinned")
  end

  it "keeps the empty state when the category contains only hidden pins" do
    create_instance("i-hidden", pinned: true, hidden: true)

    get root_path

    expect(compute_card.at_css(".resource-count").text).to eq("0 resources")
    expect(compute_card.at_css(".category-insight").text).to eq("No stored resources yet.")
    expect(compute_card.css(".category-pinned, .category-description")).to be_empty
  end
end
