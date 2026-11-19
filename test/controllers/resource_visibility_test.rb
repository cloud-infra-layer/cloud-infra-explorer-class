require "test_helper"

class ResourceVisibilityTest < ActionDispatch::IntegrationTest
  test "listing defaults to visible resources and allows searching hidden inventory" do
    bucket = resources(:assets_bucket)
    bucket.update!(hidden: true)

    get resources_path
    assert_response :success
    assert_select "tbody th", text: bucket.name, count: 0

    get resources_path, params: { visibility: "hidden", service: "s3", q: bucket.name.upcase }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody th", text: bucket.name
    assert bucket.reload.hidden?
  end

  test "structured or unsupported visibility returns bad request" do
    [ "all", [ "hidden" ], { value: "hidden" } ].each do |visibility|
      get resources_path, params: { visibility: visibility }
      assert_response :bad_request
    end
  end

  test "listing orders pins first and dashboard counts exclude hidden inventory" do
    web = resources(:web_server)
    bucket = resources(:assets_bucket)
    web.update!(name: "Alpha")
    bucket.update!(name: "Zebra", pinned: true)

    get resources_path
    assert_select "tbody th" do |nodes|
      assert_equal [ "Zebra", "Alpha" ], nodes.map(&:text)
    end

    web.update!(hidden: true)
    get dashboard_path
    assert_response :success
    assert_select "#ec2-resources .resource-count", text: "0 resources"
    assert_select "#ec2-resources table", count: 0
    assert_select "#s3-resources .resource-count", text: "1 resource"
    assert_select ".category-card .resource-count", text: "0 resources", count: 1
    assert_select ".category-card .resource-count", text: "1 resource", count: 1
    assert web.reload.hidden?
  end
end
