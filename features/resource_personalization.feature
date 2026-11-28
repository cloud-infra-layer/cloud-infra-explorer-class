
@personalization
Feature: Prioritize important cloud resources
  As a team managing AWS infrastructure
  I want to pin important resources
  So that I can find frequently used infrastructure quickly

  Background:
    Given the application has an empty resource inventory
    And the application contains an EC2 instance named "web-server"

  Scenario: Pin an important resource
    When I visit the resource inventory
    And I pin the resource "web-server"
    Then I should see "Resource pinned for the team."
    And I should see a pinned row for "web-server"

  Scenario: Unpin a resource
    When I visit the resource inventory
    And I pin the resource "web-server"
    And I unpin the resource "web-server"
    Then I should see "Resource unpinned for the team."
    And I should not see a pinned row for "web-server"

  Scenario: Hide an irrelevant resource
    When I visit the resource inventory
    And I hide the resource "web-server"
    Then I should see "Resource hidden from the team's visible inventory."
    And I should see a hidden row for "web-server"

  Scenario: Restore a hidden resource
    When I visit the resource inventory
    And I hide the resource "web-server"
    And I restore the resource "web-server"
    Then I should see "Resource restored to the team's visible inventory."
    And I should not see a hidden row for "web-server"
