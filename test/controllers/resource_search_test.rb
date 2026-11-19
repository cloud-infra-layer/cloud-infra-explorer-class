require "test_helper"

class ResourceSearchTest < ActionDispatch::IntegrationTest
  test "search matches names types and IDs while respecting category" do
    web = resources(:web_server)
    [ web.name.upcase, "EC2", web.resource_id.upcase ].each do |query|
      get resources_path, params: { q: query, service: "ec2" }
      assert_response :success
      assert_select "tbody th", text: web.name
      assert_select "tbody th", text: resources(:assets_bucket).name, count: 0
    end

    get resources_path, params: { q: "s3", service: "ec2" }
    assert_response :success
    assert_select ".empty-state", "No resources match your search in the selected category."
    assert_select "table", count: 0
  end

  test "blank query retains the normal listing" do
    get resources_path, params: { q: "   " }
    assert_response :success
    assert_select "tbody tr", count: Resource.where(provider: "aws").count
  end

  test "structured search parameters return bad request" do
    [ [ "web" ], { name: "web" } ].each do |query|
      get resources_path, params: { q: query }
      assert_response :bad_request
    end
  end

  test "search input is escaped when redisplayed" do
    query = '<script>alert("search")</script>'
    get resources_path, params: { q: query }
    assert_response :success
    assert_select "main script", count: 0
    assert_select "input[name=q]" do |inputs|
      assert_equal query, inputs.first["value"]
    end
  end
end
