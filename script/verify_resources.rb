# Run from the repository root:
# AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb
require "bundler/setup"
require "json"
require "optparse"
require_relative "../app/services/cloud_provider/adapter"

services = [ "ec2", "s3" ]
parser = OptionParser.new do |options|
  options.banner = "Usage: ruby script/verify_resources.rb [--services ec2,s3]"
  options.on("--services SERVICES", "Comma-separated services: ec2,s3 (default: both)") do |value|
    services = value.split(",", -1).map(&:strip).uniq
    unless services.any? && services.all? { |service| [ "ec2", "s3" ].include?(service) }
      raise OptionParser::InvalidArgument, "--services must contain only ec2 or s3"
    end
  end
  options.on("-h", "--help", "Show usage") do
    puts options
    exit 0
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, "Unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

result = CloudProvider::Adapter.new.list_resources(
  provider: "aws", region: ENV["AWS_REGION"], resource_types: services
)
puts JSON.pretty_generate(result)
exit(result[:errors].empty? ? 0 : 1)
