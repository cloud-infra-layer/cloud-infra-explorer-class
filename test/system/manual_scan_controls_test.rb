require "test_helper"

class ManualScanControlsTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
    options.add_argument("--no-sandbox") if ENV["CHROME_NO_SANDBOX"] == "1"
  end

  setup do
    # Close the browser on reset rather than using Capybara's wildcard CDP
    # cleanup, which newer Chrome versions reject. Preserve test isolation.
    page.driver.define_singleton_method(:reset!) { quit }

    @previous_enable_manual_scans = ENV["ENABLE_MANUAL_SCANS"]
    ENV["ENABLE_MANUAL_SCANS"] = "true"
  end

  teardown do
    if @previous_enable_manual_scans.nil?
      ENV.delete("ENABLE_MANUAL_SCANS")
    else
      ENV["ENABLE_MANUAL_SCANS"] = @previous_enable_manual_scans
    end
  end

  test "mobile and desktop controls show loading and prevent duplicate submission" do
    [ [ 1280, 900 ], [ 390, 844 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      visit dashboard_path
      select "Course testing (us-west-2)", from: "AWS environment"
      click_button "View environment"

      assert_selector ".account-details h2", text: "Course testing"
      assert_selector "form.scan-form[action='#{environment_scans_path(environments(:course_testing))}']"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=,
        page.evaluate_script("window.innerWidth")
      within ".scan-form" do
        Scan::RESOURCE_TYPES.each { |type| uncheck type.upcase }
        click_button "Refresh resources"
        assert_selector "[role=status]", text: "Select at least one service."
        check "S3"

        # Hold the browser on the page so the pending state can be inspected without sending a scan request.
        page.execute_script(<<~JS)
          document.querySelector(".scan-form").addEventListener("submit", event => event.preventDefault(), { once: true })
        JS
        click_button "Refresh resources"
        assert_button "Scanning…", disabled: true
        assert_selector "[role=status]", text: "Scan in progress."
        assert page.evaluate_script(<<~JS)
          !document.querySelector(".scan-form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        JS
      end
    end
  end
end
