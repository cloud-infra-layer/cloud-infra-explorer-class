
@manual_scan
Feature: Refresh AWS infrastructure inventory
  As an administrator managing cloud infrastructure
  I want to refresh the stored AWS inventory
  So that my team can see updated resources without losing existing data

  Background:
    Given the application has an empty resource inventory
    And the application contains an EC2 instance named "web-server"

  Scenario: Successfully discover new AWS resources
    Given AWS discovery will find a new S3 bucket
    When I visit the dashboard
    And I start a manual scan
    Then I should see "Scan completed:"
    And I should see "Latest scan:"
    And I should see "Completed"
    When I visit the resource inventory
    Then I should see "new-assets-bucket"
    And I should see "web-server"

  Scenario: Failed AWS discovery preserves existing inventory
    Given AWS discovery will fail
    When I visit the dashboard
    And I start a manual scan
    Then I should see "Scan failed."
    And I should see "Latest scan:"
    And I should see "Failed"
    When I visit the resource inventory
    Then I should see "web-server"
