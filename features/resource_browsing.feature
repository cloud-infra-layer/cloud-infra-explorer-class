Feature: Browse cloud infrastructure resources
  As a user managing cloud infrastructure
  I want to browse resources by AWS service
  So that I can inspect the infrastructure I manage

  Background:
    Given the application has an empty resource inventory
    And the application contains an EC2 instance named "web-server"
    And the application contains an S3 bucket named "assets-bucket"

  Scenario: Browse EC2 resources from the dashboard
    When I visit the dashboard
    And I click the EC2 category
    Then I should see "EC2 Resources"
    And I should see "web-server"
    And I should not see "assets-bucket"

  Scenario: Browse S3 resources from the dashboard
    When I visit the dashboard
    And I click the S3 category
    Then I should see "S3 Resources"
    And I should see "assets-bucket"
    And I should not see "web-server"

  Scenario: Return to the dashboard
    When I visit the dashboard
    And I click the EC2 category
    And I click "Back to dashboard"
    Then I should see the cloud infrastructure dashboard
