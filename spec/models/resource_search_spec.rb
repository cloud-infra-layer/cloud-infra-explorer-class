require "rails_helper"

RSpec.describe Resource, "search", type: :model do
  let(:environment) { Environment.create!(name: "Search examples", provider: "aws", region: "us-east-1") }
  let!(:web) do
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-search-web",
      name: "Production Web", region: "us-east-1", metadata: {})
  end
  let!(:bucket) do
    environment.resources.create!(provider: "aws", service: "s3", resource_id: "search-assets",
      name: "Production Assets", metadata: {})
  end

  it "matches substrings in names, service types, and resource IDs without case sensitivity" do
    { "  WEB  " => [ web ], "Ec2" => [ web ], "SEARCH-ASSETS" => [ bucket ],
      "production" => [ web, bucket ] }.each do |query, expected|
      expect(environment.resources.search(query)).to match_array(expected)
    end
  end

  it "leaves a blank search unrestricted and combines searches with category filters" do
    [ nil, "", "   " ].each do |query|
      expect(environment.resources.search(query)).to contain_exactly(web, bucket)
    end
    expect(environment.resources.where(service: "s3").search("production")).to contain_exactly(bucket)
    expect(environment.resources.where(service: "ec2").search("s3")).to be_empty
  end

  it "treats wildcard characters, backslashes, and SQL-looking input as literal text" do
    [ "%", "_", "\\", "' OR 1=1 --" ].each do |query|
      web.update!(name: "Literal #{query} value")
      expect(environment.resources.search(query)).to contain_exactly(web)
    end
  end

  it "does not widen an environment-scoped search" do
    other = Environment.create!(name: "Other search environment", provider: "aws", region: "us-east-1")
    copy = web.dup
    copy.environment = other
    copy.save!

    expect(environment.resources.search("web")).to contain_exactly(web)
  end
end
