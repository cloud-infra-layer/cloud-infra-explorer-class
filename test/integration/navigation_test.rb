require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "shared navigation works across dashboard and category pages" do
    pages = {
      root_path => "Dashboard",
      home_index_path => "Dashboard",
      resources_path(service: "ec2") => "EC2 Resources",
      resources_path(service: "s3") => "S3 Resources"
    }

    pages.each do |path, active_label|
      get path

      assert_response :success
      assert_select "html[lang=en]"
      assert_select "header a[href=?]", root_path, text: "Cloud Infrastructure Explorer"
      assert_select "a.skip-link[href='#main-content']"
      assert_select "main#main-content", count: 1
      assert_select "nav[aria-label='Primary navigation']" do
        assert_select "a[href=?]", root_path, text: "Dashboard"
        assert_select "a[href=?]", resources_path(service: "ec2"), text: "EC2 Resources"
        assert_select "a[href=?]", resources_path(service: "s3"), text: "S3 Resources"
        assert_select "a[aria-current=page]", count: 1, text: active_label
      end
    end
  end

  test "navigation routes resolve to their intended controllers" do
    assert_routing "/", controller: "home", action: "index"
    assert_recognizes({ controller: "home", action: "index" }, "/home/index")
    assert_routing "/resources", controller: "resources", action: "index"
  end
end
