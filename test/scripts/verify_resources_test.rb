require "minitest/autorun"
require "open3"
require "json"
require "rbconfig"

class VerifyResourcesScriptTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  RUNNER = <<~'RUBY_CODE'
    require_relative "app/services/cloud_provider/adapter"
    class CloudProvider::Adapter
      def list_resources(context)
        raise "Discovery must not run" if ENV["VERIFY_TEST_NO_DISCOVERY"]
        { resources: [context], errors: ENV["VERIFY_TEST_FAILURE"] ? [{ code: "aws_api_error" }] : [] }
      end
    end
    load "script/verify_resources.rb"
  RUBY_CODE

  def test_default_services_and_region
    output, error, status = run_script
    assert status.success?, error
    assert_equal({ "provider" => "aws", "region" => "us-east-2", "resource_types" => [ "ec2", "s3" ] }, JSON.parse(output)["resources"].first)
  end

  def test_service_selection
    { "ec2" => [ "ec2" ], "s3" => [ "s3" ], "s3,ec2,s3" => [ "s3", "ec2" ] }.each do |selection, expected|
      output, error, status = run_script("--services", selection)
      assert status.success?, error
      assert_equal expected, JSON.parse(output)["resources"].first["resource_types"]
    end
  end

  def test_invalid_arguments_fail_before_discovery
    [ [ "--services", "lambda" ], [ "--services", "" ], [ "--services", "ec2," ],
      [ "--services" ], [ "--unknown" ], [ "ec2" ] ].each do |arguments|
      output, error, status = run_script(*arguments, env: { "VERIFY_TEST_NO_DISCOVERY" => "1" })
      assert_equal 2, status.exitstatus, error
      assert_empty output
      assert_includes error, "Usage:"
    end
  end

  def test_help_does_not_discover
    output, error, status = run_script("--help", env: { "VERIFY_TEST_NO_DISCOVERY" => "1" })
    assert status.success?, error
    assert_includes output, "--services"
  end

  def test_discovery_errors_return_json_and_failure_status
    output, _, status = run_script(env: { "VERIFY_TEST_FAILURE" => "1" })
    assert_equal 1, status.exitstatus
    assert_equal "aws_api_error", JSON.parse(output)["errors"].first["code"]
  end

  private

  def run_script(*arguments, env: {})
    Open3.capture3({ "AWS_REGION" => "us-east-2" }.merge(env), RbConfig.ruby,
      "-e", RUNNER, "--", *arguments, chdir: ROOT)
  end
end
