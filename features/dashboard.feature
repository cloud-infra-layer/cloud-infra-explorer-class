Feature: Cloud infrastructure dashboard
  As a user managing cloud infrastructure
  I want to view my stored AWS resources
  So that I can understand what infrastructure exists

  Scenario: Viewing the dashboard
    Given the application has an empty resource inventory
    When I visit the dashboard
    Then I should see the cloud infrastructure dashboard
    And I should see the EC2 and S3 resource categories

  Scenario: Viewing stored infrastructure
    Given the application contains an EC2 instance named "web-server"
    And the application contains an S3 bucket named "assets-bucket"
    When I visit the dashboard
    Then I should see "web-server"
    And I should see "assets-bucket"

  Scenario: Viewing an empty inventory
    Given the application has an empty resource inventory
    When I visit the dashboard
    Then I should see "0 resources"
