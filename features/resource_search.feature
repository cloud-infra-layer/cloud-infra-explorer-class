Feature: Search and filter stored resources
  As a team member
  I want to search and filter our stored AWS inventory
  So that I can quickly find the resources relevant to my work

  Background:
    Given the application has an empty resource inventory
    And the application contains an EC2 instance named "production-web"
    And the application contains an S3 bucket named "production-assets"

  Scenario: Find a resource by name
    When I visit the resource listing
    And I search for "production-web"
    Then the resource results should include "production-web"
    And the resource results should not include "production-assets"

  Scenario: Narrow matching resources by category
    When I visit the resource listing
    And I search for "production"
    Then the resource results should include "production-web"
    And the resource results should include "production-assets"
    When I filter by "Compute"
    Then the resource results should include "production-web"
    And the resource results should not include "production-assets"
    When I filter by "All categories"
    Then the resource results should include "production-web"
    And the resource results should include "production-assets"

  Scenario: Search returns no matches
    When I visit the resource listing
    And I search for "nonexistent-resource"
    Then I should see "No resources match the current filters."
    And the resource results should be empty

  Scenario: Clear search while preserving the category
    When I visit the resource listing
    And I filter by "Compute"
    And I search for "nonexistent-resource"
    Then the resource results should be empty
    When I click "Clear search"
    Then the search query should be empty
    And the resource results should include "production-web"
    And the resource results should not include "production-assets"
