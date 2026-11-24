require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "shared navigation works across overview and category pages" do
    pages = {
      root_path => "Overview",
      home_index_path => "Overview",
      resources_path(service: "ec2") => "Compute",
      resources_path(service: "s3") => "Storage",
      resources_path(pinned: "1") => "Pinned"
    }

    pages.each do |path, active_label|
      get path

      assert_response :success
      assert_select "html[lang=en]"
      assert_select "header a[href=?]", root_path, text: "Cloud Infrastructure Explorer"
      assert_select "a.skip-link[href='#main-content']"
      assert_select "main#main-content", count: 1
      assert_select "nav[aria-label='Primary navigation']" do
        assert_select "a[href=?]", root_path, text: "Overview"
        assert_select "a[href=?]", resources_path(service: "ec2"), text: "Compute"
        assert_select "a[href=?]", resources_path(service: "s3"), text: "Storage"
        assert_select "a[href=?]", resources_path(pinned: "1"), text: "Pinned"
        assert_select "a[aria-current=page]", count: 1, text: active_label
      end
    end
  end

  test "navigation routes resolve to their intended controllers" do
    assert_routing "/", controller: "dashboard", action: "index"
    assert_recognizes({ controller: "home", action: "index" }, "/home/index")
    assert_routing "/resources", controller: "resources", action: "index"
    assert_routing({ path: "/resources/1", method: :get }, { controller: "resources", action: "show", id: "1" })
  end
end
