require "rails_helper"

RSpec.describe "Manual scans", type: :request do
  let(:environment) { Environment.create!(name: "Scan request specs", provider: "aws", region: "us-east-2") }
  let(:path) { environment_scans_path(environment) }
  let(:headers) { { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("scan-tester", "test-password") } }
  let(:record) do
    { provider: "aws", service: "ec2", resource_id: "i-request-scan", name: "Request server",
      region: environment.region, metadata: { state: "running" }, console_url: nil }
  end
  let(:result) { { resources: [ record ], errors: [] } }
  let(:adapter) { instance_double(CloudProvider::Adapter, list_resources: result) }

  around do |example|
    keys = %w[ENABLE_MANUAL_SCANS SCAN_ADMIN_USERNAME SCAN_ADMIN_PASSWORD]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["ENABLE_MANUAL_SCANS"] = "true"
    ENV["SCAN_ADMIN_USERNAME"] = "scan-tester"
    ENV["SCAN_ADMIN_PASSWORD"] = "test-password"
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    # Exercise the actual coordinator and persistence behind the HTTP boundary;
    # replace only discovery so no request can reach AWS.
    allow(CloudProvider::Adapter).to receive(:new).and_return(adapter)
  end

  %w[ENABLE_MANUAL_SCANS SCAN_ADMIN_USERNAME SCAN_ADMIN_PASSWORD].each do |key|
    it "disables scans when #{key} is missing" do
      ENV.delete(key)
      expect(adapter).not_to receive(:list_resources)
      post path, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(environment.scans).to be_empty
    end
  end

  it "rejects missing and incorrect credentials without creating scans" do
    expect(adapter).not_to receive(:list_resources)
    [ {}, { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("scan-tester", "wrong") } ].each do |auth|
      post path, headers: auth
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include("Basic")
    end
    expect(environment.scans).to be_empty
  end

  [ [], [ "lambda" ], [ "ec2", "ec2" ], "ec2", { service: "ec2" } ].each do |types|
    it "rejects invalid resource types #{types.inspect} before discovery" do
      expect(adapter).not_to receive(:list_resources)
      # JSON preserves an explicit empty array; form encoding can omit it and
      # accidentally exercise the controller's default-types behavior instead.
      post path, headers: headers, params: { resource_types: types }, as: :json
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("Select valid EC2/S3 resource types.")
      expect(environment.scans).to be_empty
    end
  end

  it "persists a default two-service scan and shows success feedback after redirect" do
    expect(adapter).to receive(:list_resources).with(provider: "aws", region: environment.region, resource_types: %w[ec2 s3]).and_return(result)
    post path, headers: headers
    expect(response).to redirect_to(dashboard_path)
    expect(environment.scans.sole).to have_attributes(status: "completed", created_count: 1, discovered_count: 1)
    expect(environment.resources.sole.name).to eq("Request server")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("[role=status]").text).to include("1 new, 0 updated resources")
  end

  it "passes an explicit single-service request to discovery" do
    expect(adapter).to receive(:list_resources).with(provider: "aws", region: environment.region, resource_types: [ "ec2" ]).and_return(result)
    post path, headers: headers, params: { resource_types: [ "ec2" ] }
    expect(environment.scans.sole.resource_types).to eq([ "ec2" ])
  end

  it "shows partial feedback and preserves personalized inventory for a failed service" do
    existing = environment.resources.create!(record.merge(pinned: true, hidden: true))
    original = existing.attributes
    allow(adapter).to receive(:list_resources).and_return(resources: [], errors: [ { resource_type: "ec2", code: "aws_api_error", message: "EC2 unavailable." } ])
    post path, headers: headers
    expect(response).to redirect_to(dashboard_path)
    expect(environment.scans.sole.status).to eq("partial")
    expect(flash[:notice]).to include("Scan partially completed")
    expect(existing.reload.attributes).to eq(original)
  end

  it "shows safe failure feedback when discovery raises" do
    allow(adapter).to receive(:list_resources).and_raise(StandardError, "private-sdk-value")
    post path, headers: headers
    expect(response).to redirect_to(dashboard_path)
    expect(environment.scans.sole.status).to eq("failed")
    expect(flash[:notice]).to eq("Scan failed. Previously stored resources were preserved.")
    follow_redirect!
    expect(response.body).not_to include("private-sdk-value")
  end

  it "returns 404 for an unknown environment without discovery" do
    expect(adapter).not_to receive(:list_resources)
    post environment_scans_path(environment_id: 0), headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "does not allow GET to initiate a scan" do
    expect(adapter).not_to receive(:list_resources)
    get path, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(environment.scans).to be_empty
  end

  it "requires a CSRF token when forgery protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    expect(adapter).not_to receive(:list_resources)
    post path, headers: headers
    expect(response).to have_http_status(422)
    expect(environment.scans).to be_empty
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "shows one enabled refresh form and the last completed scan for the selected environment" do
    # The adapter setup already evaluates and caches this environment. Keep its
    # row while removing other test data for deterministic dashboard selection.
    selected = environment
    Scan.delete_all
    Resource.delete_all
    Environment.where.not(id: selected.id).delete_all
    completed_at = 1.hour.ago.change(sec: 0)
    selected.scans.create!(resource_types: %w[ec2 s3], status: "completed",
      started_at: completed_at - 1.minute, completed_at: completed_at)
    selected.scans.create!(resource_types: %w[ec2 s3], status: "partial",
      started_at: 30.minutes.ago, completed_at: 29.minutes.ago,
      error_details: [ { resource_type: "s3", code: "aws_api_error", message: "S3 unavailable." } ])

    get dashboard_path
    document = Nokogiri::HTML(response.body)
    expect(document.css("form[action='#{environment_scans_path(selected)}']").size).to eq(1)
    expect(Time.iso8601(document.at_css(".connected-account-card time")["datetime"]).to_i).to eq(completed_at.to_i)
    ENV["ENABLE_MANUAL_SCANS"] = "false"
    get dashboard_path
    expect(Nokogiri::HTML(response.body).css("form[action$='/scans']")).to be_empty
  end
end
