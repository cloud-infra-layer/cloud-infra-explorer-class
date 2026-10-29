require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "homepage and dashboard route render the dashboard" do
    [ root_url, dashboard_url ].each do |url|
      get url

      assert_response :success
      assert_select "h1", "Cloud Infrastructure Explorer"
      assert_select "section#ec2-resources"
      assert_select "section#s3-resources"
    end
  end

  test "displays stored resources in their service sections with database counts" do
    get dashboard_url

    assert_response :success
    { "ec2" => resources(:web_server), "s3" => resources(:assets_bucket) }.each do |service, resource|
      assert_select "section##{service}-resources" do
        assert_select ".resource-count", "1 resource"
        assert_select "tbody tr", count: 1
        assert_select "tr#resource-#{resource.id}" do
          assert_select "td", text: resource.name
          assert_select "td", text: resource.environment.name
          assert_select "td", text: resource.resource_id
          assert_select "td", text: resource.region.presence || "Not specified"
        end
      end
    end
  end

  test "includes the same AWS identifier from different environments without deduplication" do
    original = resources(:web_server)
    second = original.dup
    second.environment = environments(:course_testing)
    second.save!

    get dashboard_url

    assert_response :success
    assert_select "section#ec2-resources" do
      assert_select ".resource-count", "2 resources"
      assert_select "tbody tr", count: 2
      [ original, second ].each do |resource|
        assert_select "tr#resource-#{resource.id}" do
          assert_select "td", text: resource.environment.name
          assert_select "td", text: original.resource_id
        end
      end
    end
  end

  test "renders an empty category while keeping the other category visible" do
    Resource.where(service: "s3").delete_all

    get dashboard_url

    assert_response :success
    assert_select "section#s3-resources" do
      assert_select ".resource-count", "0 resources"
      assert_select ".empty-state", "No S3 buckets stored yet."
      assert_select "table", count: 0
    end
    assert_select "section#ec2-resources tbody tr", count: 1
  end

  test "renders an empty inventory successfully" do
    Resource.delete_all

    get root_url

    assert_response :success
    assert_select ".resource-count", text: "0 resources", count: 2
    assert_select ".empty-state", count: 2
    assert_select "table", count: 0
  end

  test "escapes resource names in HTML" do
    resource = resources(:web_server)
    resource.update!(name: "<script>alert('example')</script>")

    get dashboard_url

    assert_response :success
    assert_select "tr#resource-#{resource.id} td", text: resource.name
    assert_select "main script", count: 0
  end
end
