Feature: Explore cloud spend trends
  As a team reviewing infrastructure cost
  I want monthly spend insights and a service cost chart
  So that I can see trends without leaving the overview

  Background:
    Given the application has an empty resource inventory
    And the application contains monthly cost snapshots for the demo environment

  Scenario: Overview shows spend insights and a color-coded cost chart
    When I visit the dashboard
    Then I should see the cost insights for "November 2026"
    And I should see "Monthly spend"
    And I should see "MoM"
    And I should see "YoY"
    And I should see the Cost Explorer chart
    And the cost chart legend should include "AWS Bedrock"
    And the cost chart range "1M" should not be available
    And the active cost chart range should be "6M"

  Scenario: Switch the Cost Explorer time range
    When I visit the dashboard
    And I choose the cost chart range "3M"
    Then the active cost chart range should be "3M"
    And I should see the Cost Explorer chart
    When I choose the cost chart range "Max"
    Then the active cost chart range should be "Max"
    And I should see the Cost Explorer chart
