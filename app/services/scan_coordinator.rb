
class ScanCoordinator
  def initialize(environment:, adapter: CloudProvider::Adapter.new)
    @environment = environment
    @adapter = adapter
  end

  def call(resource_types: [ "ec2" ])
    connection_context = {
      provider: @environment.provider,
      region: @environment.region,
      resource_types: resource_types
    }

    @adapter.list_resources(connection_context)
  end
end
