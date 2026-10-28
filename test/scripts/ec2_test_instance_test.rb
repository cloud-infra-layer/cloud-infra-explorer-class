require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"

class Ec2TestInstanceScriptTest < Minitest::Test
  SCRIPT = File.expand_path("../../script/ec2_test_instance.sh", __dir__)
  FAKE_AWS = <<~'RUBY'
    #!/usr/bin/env ruby
    require "json"
    File.open(ENV.fetch("AWS_TEST_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }
    args = ARGV.drop(5) # Explicit profile, region, and no-cli-pager
    query = args[args.index("--query").to_i + 1]
    case args.first(2)
    when ["sts", "get-caller-identity"]
      puts ENV.fetch("AWS_TEST_ACCOUNT", "821058455060")
    when ["ec2", "describe-instances"]
      puts ENV.fetch("AWS_TEST_INSTANCES", "")
    when ["ec2", "describe-security-groups"]
      puts case query
      when "SecurityGroups[0].IpPermissions" then ENV.fetch("AWS_TEST_INGRESS", "[]")
      when "SecurityGroups[0].IpPermissionsEgress" then ENV.fetch("AWS_TEST_EGRESS", "[]")
      when "SecurityGroups[0].VpcId" then "vpc-12345678"
      else ENV.fetch("AWS_TEST_GROUPS", "")
      end
    when ["ec2", "describe-subnets"] then puts "vpc-12345678"
    when ["ssm", "get-parameter"] then puts "ami-12345678"
    when ["ec2", "describe-images"] then puts "/dev/xvda"
    when ["ec2", "create-security-group"] then puts "sg-12345678"
    when ["ec2", "run-instances"]
      exit 1 if ENV["AWS_TEST_LAUNCH_FAILURE"]
      puts "i-12345678"
    when ["ec2", "wait"], ["ec2", "terminate-instances"], ["ec2", "delete-security-group"],
      ["ec2", "revoke-security-group-egress"]
      puts "{}"
    else
      warn "Unexpected AWS call: #{args.inspect}"
      exit 1
    end
  RUBY

  def setup
    @directory = Dir.mktmpdir("ec2-script-test")
    File.write(File.join(@directory, "aws"), FAKE_AWS)
    File.chmod(0o700, File.join(@directory, "aws"))
    @log = File.join(@directory, "calls.jsonl")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_wrong_account_aborts_before_ec2_access
    output, status = run_script("create", "test-run", "subnet-12345678", env: { "AWS_TEST_ACCOUNT" => "000000000000" })
    refute status.success?
    assert_includes output, "Wrong AWS account"
    assert_equal [ [ "sts", "get-caller-identity" ] ], calls.map { |args| args[5, 2] }
  end

  def test_invalid_run_id_aborts_without_aws_calls
    _, status = run_script("cleanup", "*")
    refute status.success?
    assert_empty calls
  end

  def test_launch_is_scoped_and_uses_secure_defaults
    _, status = run_script("create", "test-run", "subnet-12345678")
    assert status.success?
    assert calls.all? { |args| args.first(5) == [ "--profile", "cloud-explorer-setup", "--region", "us-east-2", "--no-cli-pager" ] }
    launch = calls.find { |args| args[5, 2] == [ "ec2", "run-instances" ] }
    assert_equal "1", launch[launch.index("--count") + 1]
    assert_includes launch.join(" "), "AssociatePublicIpAddress=false"
    assert_includes launch.join(" "), "Encrypted=true,DeleteOnTermination=true"
    assert_includes launch, "CpuCredits=standard"
    assert_includes launch, "HttpTokens=required,HttpPutResponseHopLimit=1"
    refute_includes launch, "--key-name"
    refute_includes launch, "--iam-instance-profile"
    assert_equal "cloud-explorer-test-run", launch[launch.index("--client-token") + 1]
  end

  def test_existing_instance_does_not_launch_another
    _, status = run_script("create", "test-run", "subnet-12345678", env: { "AWS_TEST_INSTANCES" => "i-12345678" })
    assert status.success?
    refute calls.any? { |args| [ "create-security-group", "run-instances" ].include?(args[6]) }
  end

  def test_unexpected_inbound_rules_prevent_launch
    _, status = run_script("create", "test-run", "subnet-12345678",
      env: { "AWS_TEST_GROUPS" => "sg-12345678", "AWS_TEST_INGRESS" => '[{"IpProtocol":"-1"}]' })
    refute status.success?
    refute calls.any? { |args| args[6] == "run-instances" }
  end

  def test_default_egress_is_revoked_before_launch
    permissions = '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
    _, status = run_script("create", "test-run", "subnet-12345678", env: { "AWS_TEST_EGRESS" => permissions })
    assert status.success?
    revoke = calls.find { |args| args[6] == "revoke-security-group-egress" }
    assert_equal permissions, revoke[revoke.index("--ip-permissions") + 1]
    launch = calls.find { |args| args[6] == "run-instances" }
    assert_operator calls.index(revoke), :<, calls.index(launch)
  end

  def test_cleanup_refuses_multiple_instances_before_deletion
    _, status = run_script("cleanup", "test-run", env: { "AWS_TEST_INSTANCES" => "i-12345678\ti-abcdef12" })
    refute status.success?
    refute calls.any? { |args| [ "terminate-instances", "delete-security-group" ].include?(args[6]) }
  end

  def test_cleanup_targets_only_tagged_instance_and_group
    _, status = run_script("cleanup", "test-run", env: { "AWS_TEST_INSTANCES" => "i-12345678", "AWS_TEST_GROUPS" => "sg-12345678" })
    assert status.success?
    lookups = calls.select { |args| args.include?("--filters") }
    assert lookups.all? { |args| args.include?("Name=tag:TestRun,Values=test-run") && args.include?("Name=tag:ManagedBy,Values=cloud-explorer-live-test") }
    termination = calls.find { |args| args[6] == "terminate-instances" }
    assert_equal "i-12345678", termination[termination.index("--instance-ids") + 1]
    deletion = calls.find { |args| args[6] == "delete-security-group" }
    assert_equal "sg-12345678", deletion[deletion.index("--group-id") + 1]
    assert_operator calls.index(termination), :<, calls.index(deletion)
  end

  def test_empty_cleanup_is_safe_to_repeat
    _, status = run_script("cleanup", "test-run")
    assert status.success?
    refute calls.any? { |args| [ "terminate-instances", "delete-security-group" ].include?(args[6]) }
  end

  def test_launch_failure_leaves_recovery_instructions
    output, status = run_script("create", "test-run", "subnet-12345678", env: { "AWS_TEST_LAUNCH_FAILURE" => "1" })
    refute status.success?
    assert_includes output, "cleanup test-run"
  end

  private

  def run_script(*arguments, env: {})
    Open3.capture2e({ "PATH" => "#{@directory}:#{ENV.fetch('PATH')}", "AWS_TEST_LOG" => @log }.merge(env),
      "bash", SCRIPT, *arguments)
  end

  def calls
    File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) } : []
  end
end
