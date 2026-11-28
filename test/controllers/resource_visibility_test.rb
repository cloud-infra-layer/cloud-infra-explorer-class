require "test_helper"

class ResourceVisibilityTest < ActionDispatch::IntegrationTest
  test "listing includes hidden rows and supports category narrowing" do
    bucket = resources(:assets_bucket)
    bucket.update!(hidden: true)

    get resources_path
    assert_response :success
    assert_select "tbody th", text: bucket.name, count: 1
    assert_select "tr.resource-row--hidden th", text: bucket.name

    get resources_path, params: { category: "storage" }
    assert_response :success
    assert_select "tbody th", text: bucket.name, count: 1
    assert_select "tbody th", text: resources(:web_server).name, count: 0

    get resources_path, params: { categories: %w[compute storage], q: bucket.name.upcase }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody th", text: bucket.name
  end

  test "unsupported category returns not found" do
    get resources_path, params: { category: "lambda" }
    assert_response :not_found

    get resources_path, params: { categories: %w[compute lambda] }
    assert_response :not_found
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
    assert_select "a.category-card[href=?]", resources_path(category: "compute") do
      assert_select ".resource-count", text: "0 resources"
    end
    assert_select "a.category-card[href=?]", resources_path(category: "storage") do
      assert_select ".resource-count", text: "1 resource"
    end
  end
end
