require "rails_helper"

RSpec.describe "Protected resource personalization", type: :request do
  let(:environment) { Environment.create!(name: "Protected actions", provider: "aws", region: "us-east-1") }
  let(:resource) do
    environment.resources.create!(provider: "aws", service: "ec2", resource_id: "i-protected",
      name: "Protected server", metadata: {})
  end
  let(:auth_headers) do
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("test-editor", "test-password") }
  end

  around do |example|
    keys = %w[ENABLE_RESOURCE_PERSONALIZATION RESOURCE_ADMIN_USERNAME RESOURCE_ADMIN_PASSWORD ENABLE_MANUAL_SCANS]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "true"
    ENV["RESOURCE_ADMIN_USERNAME"] = "test-editor"
    ENV["RESOURCE_ADMIN_PASSWORD"] = "test-password"
    ENV["ENABLE_MANUAL_SCANS"] = "false"
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    expect(CloudProvider::Adapter).not_to receive(:new)
    expect(ScanCoordinator).not_to receive(:new)
  end

  { pin: [ :pinned, true ], unpin: [ :pinned, false ], hide: [ :hidden, true ], restore: [ :hidden, false ] }.each do |action, (attribute, value)|
    context action.to_s do
      let(:path) { public_send("#{action}_resource_path", resource) }

      it "sets only its intended state and is safe to repeat with scanning disabled" do
        resource.update!(attribute => !value)
        original = resource.reload.attributes.except(attribute.to_s, "updated_at")
        2.times do
          patch path, headers: auth_headers, params: { resource: { name: "Injected", pinned: !value, hidden: !value }, return_to: "https://example.com" }
          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(resources_path)
          expect(resource.reload[attribute]).to eq(value)
          expect(resource.attributes.except(attribute.to_s, "updated_at")).to eq(original)
        end
      end

      it "rejects missing and incorrect credentials without changing the resource" do
        original = resource.attributes
        [ {}, { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("test-editor", "wrong") } ].each do |headers|
          patch path, headers: headers
          expect(response).to have_http_status(:unauthorized)
          expect(response.headers["WWW-Authenticate"]).to include("Basic")
          expect(resource.reload.attributes).to eq(original)
        end
      end

      it "returns 404 when disabled or incompletely configured even with valid credentials" do
        original = resource.attributes
        %w[ENABLE_RESOURCE_PERSONALIZATION RESOURCE_ADMIN_USERNAME RESOURCE_ADMIN_PASSWORD].each do |key|
          saved = ENV.delete(key)
          begin
            patch path, headers: auth_headers
            expect(response).to have_http_status(:not_found)
            expect(resource.reload.attributes).to eq(original)
          ensure
            ENV[key] = saved
          end
        end
      end

      it "does not expose the action through GET" do
        original = resource.attributes
        get path, headers: auth_headers
        expect(response).to have_http_status(:not_found)
        expect(resource.reload.attributes).to eq(original)
      end
    end
  end

  it "finds hidden resources for restoration and preserves their pin" do
    resource.update!(pinned: true, hidden: true)
    patch restore_resource_path(resource), headers: auth_headers
    expect(resource.reload).not_to be_hidden
    expect(resource).to be_pinned
  end

  it "returns 404 for a missing resource after authentication" do
    patch pin_resource_path(id: 0), headers: auth_headers
    expect(response).to have_http_status(:not_found)
  end

  it "keeps resource reads available when personalization is disabled" do
    ENV["ENABLE_RESOURCE_PERSONALIZATION"] = "false"
    get resources_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects tokenless writes when Rails CSRF protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    original = resource.attributes
    patch pin_resource_path(resource), headers: auth_headers
    expect(response).to have_http_status(422)
    expect(resource.reload.attributes).to eq(original)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
