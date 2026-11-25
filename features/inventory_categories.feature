Feature: Filter inventory by category
  As a team browsing stored cloud resources
  I want to multi-select categories from the inventory page
  So that I can focus on the services I care about without separate pages

  Background:
    Given the application has an empty resource inventory
    And the application contains an EC2 instance named "web-server"
    And the application contains an S3 bucket named "assets-bucket"

  Scenario: Homepage category cards open a single-category inventory
    When I visit the dashboard
    And I click the EC2 category
    Then the Compute category filter should be active
    And the resource results should include "web-server"
    And the resource results should not include "assets-bucket"

  Scenario: Multi-select categories from inventory chips
    When I visit the resource inventory
    And I filter by "Compute"
    Then the resource results should include "web-server"
    And the resource results should not include "assets-bucket"
    When I add the Storage category filter
    Then the resource results should include "web-server"
    And the resource results should include "assets-bucket"

  Scenario: Metadata includes the resource ID
    When I visit the resource inventory
    Then the inventory table should use a Metadata column
    And the metadata for "web-server" should include resource ID "i-cucumber-001"
