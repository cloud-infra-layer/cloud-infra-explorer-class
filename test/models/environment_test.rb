require "test_helper"

class EnvironmentTest < ActiveSupport::TestCase
  test "cannot destroy an environment that contains resources" do
    environment = environments(:course_development)

    assert_no_difference [ "Environment.count", "Resource.count" ] do
      assert_not environment.destroy
    end

    assert environment.errors[:base].any?
  end

  test "can destroy an environment without resources" do
    assert_difference "Environment.count", -1 do
      environments(:course_testing).destroy!
    end
  end

  test "persists a valid AWS environment" do
    environment = Environment.new(name: "Course staging", provider: "aws", region: "us-east-1")

    assert_difference "Environment.count", 1 do
      environment.save!
    end

    environment.reload
    assert_equal "Course staging", environment.name
    assert_equal "aws", environment.provider
    assert_equal "us-east-1", environment.region
  end

  test "requires a name, provider, and region" do
    %i[name provider region].each do |attribute|
      environment = environments(:course_development).dup
      environment[attribute] = " "

      assert_not environment.valid?
      assert_includes environment.errors[attribute], "can't be blank"
    end
  end

  test "rejects unsupported providers" do
    environment = environments(:course_development).dup
    environment.provider = "azure"

    assert_not environment.valid?
    assert_includes environment.errors[:provider], "is not included in the list"
  end

  test "allows AWS regions beyond the initial region" do
    environment = environments(:course_testing).dup

    assert environment.valid?, environment.errors.full_messages.join(", ")
  end
end
