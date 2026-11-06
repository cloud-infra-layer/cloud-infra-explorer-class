require "test_helper"

class ScanTest < ActiveSupport::TestCase
  test "persists a running scan with defaults and its environment" do
    scan = build_scan

    assert_difference "Scan.count", 1 do
      scan.save!
    end

    scan.reload
    assert_equal environments(:course_testing), scan.environment
    assert_includes scan.environment.scans, scan
    assert_equal "running", scan.status
    assert_equal %w[ec2 s3], scan.resource_types
    assert_equal [ 0, 0, 0 ], [ scan.discovered_count, scan.created_count, scan.updated_count ]
    assert_equal [], scan.error_details
    assert_nil scan.completed_at
  end

  test "persists each finished status with counts and structured errors" do
    %w[completed partial failed].each do |status|
      scan = build_scan
      details = status == "completed" ? [] : [ safe_error ]
      scan.update!(status: status, completed_at: scan.started_at + 1.second,
        discovered_count: 2, created_count: 1, updated_count: 1, error_details: details)

      scan.reload
      assert_equal status, scan.status
      assert_equal details, scan.error_details
      assert_equal [ 2, 1, 1 ], [ scan.discovered_count, scan.created_count, scan.updated_count ]
    end
  end

  test "rejects missing environment, start time, and unsupported status" do
    scan = build_scan
    scan.assign_attributes(environment: nil, started_at: nil, status: "unknown")

    assert_not scan.valid?
    %i[environment started_at status].each { |attribute| assert scan.errors[attribute].any? }
  end

  test "requires supported unique requested service strings" do
    [ nil, [], "ec2", {}, [ "lambda" ], [ "ec2", "ec2" ], [ nil ] ].each do |types|
      scan = build_scan
      scan.resource_types = types

      assert_not scan.valid?
      assert scan.errors[:resource_types].any?
    end

    [ [ "ec2" ], [ "s3" ], %w[s3 ec2] ].each do |types|
      scan = build_scan
      scan.resource_types = types
      assert scan.valid?, scan.errors.full_messages.join(", ")
    end
  end

  test "counts must be nonnegative integers" do
    %i[discovered_count created_count updated_count].each do |attribute|
      [ nil, -1, 1.5, "invalid" ].each do |value|
        scan = build_scan
        scan[attribute] = value

        assert_not scan.valid?
        assert scan.errors[attribute].any?
      end
    end
  end

  test "stored error details do not replace Rails validation errors" do
    scan = build_scan
    scan.error_details = [ { resource_type: "s3", code: "aws_api_error", message: "S3 discovery failed." } ]
    scan.save!

    assert_equal [ safe_error ], scan.reload.error_details
    assert_kind_of ActiveModel::Errors, scan.errors

    [ nil, {}, "exception", [ "exception" ], [ {} ],
      [ safe_error.merge("message" => " ") ], [ safe_error.merge("code" => 123) ],
      [ safe_error.merge("raw_exception" => "untrusted details") ] ].each do |details|
      scan.error_details = details
      assert_not scan.valid?
      assert scan.errors[:error_details].any?
    end
  end

  test "completion time is consistent with status and start time" do
    scan = build_scan
    scan.completed_at = scan.started_at
    assert_not scan.valid?
    assert scan.errors[:completed_at].any?

    %w[completed partial failed].each do |status|
      scan.assign_attributes(status: status, completed_at: nil)
      assert_not scan.valid?
      assert scan.errors[:completed_at].any?

      scan.completed_at = scan.started_at - 1.second
      assert_not scan.valid?
      assert scan.errors[:completed_at].any?

      scan.completed_at = scan.started_at
      assert scan.valid?, scan.errors.full_messages.join(", ")
    end
  end

  test "database enforces status, nonnegative counts, and environment foreign key" do
    scan = build_scan
    scan.save!

    [ { status: "unknown" }, { discovered_count: -1 }, { created_count: -1 }, { updated_count: -1 } ].each do |attributes|
      assert_raises ActiveRecord::StatementInvalid do
        Scan.transaction(requires_new: true) { scan.update_columns(attributes) }
      end
      scan.reload
    end

    assert_raises ActiveRecord::InvalidForeignKey do
      Scan.transaction(requires_new: true) { scan.environment.delete }
    end
  end

  private

  def build_scan
    environments(:course_testing).scans.build(resource_types: %w[ec2 s3], started_at: Time.current)
  end

  def safe_error
    { "resource_type" => "s3", "code" => "aws_api_error", "message" => "S3 discovery failed." }
  end
end
