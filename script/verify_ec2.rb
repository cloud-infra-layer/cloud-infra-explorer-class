# Run from the repository root:
# AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_ec2.rb
require "bundler/setup"
require "json"
require_relative "../app/services/cloud_provider/adapter"

result = CloudProvider::Adapter.new.list_resources(
  provider: "aws", region: ENV["AWS_REGION"], resource_types: [ "ec2" ]
)
puts JSON.pretty_generate(result)
exit(result[:errors].empty? ? 0 : 1)
