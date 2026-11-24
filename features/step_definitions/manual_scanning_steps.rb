
Before("@manual_scan") do
  @previous_scan_settings = {
    "ENABLE_MANUAL_SCANS" => ENV["ENABLE_MANUAL_SCANS"]
  }

  ENV["ENABLE_MANUAL_SCANS"] = "true"

  @original_adapter_new = CloudProvider::Adapter.method(:new)
end

After("@manual_scan") do
  if @original_adapter_new
    CloudProvider::Adapter.define_singleton_method(
      :new, @original_adapter_new
    )
  end

  @previous_scan_settings.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end

Given("AWS discovery will find a new S3 bucket") do
  adapter = Object.new

  adapter.define_singleton_method(:list_resources) do |**_options|
    {
      resources: [
        {
          provider: "aws",
          service: "s3",
          resource_id: "new-assets-bucket",
          name: "new-assets-bucket",
          region: "us-east-1",
          metadata: {},
          console_url: nil
        }
      ],
      errors: []
    }
  end

  CloudProvider::Adapter.define_singleton_method(:new) { adapter }
end

Given("AWS discovery will fail") do
  adapter = Object.new

  adapter.define_singleton_method(:list_resources) do |**_options|
    raise StandardError, "Simulated AWS connection failure"
  end

  CloudProvider::Adapter.define_singleton_method(:new) { adapter }
end

When("I start a manual scan") do
  click_button "Refresh resources"
end
