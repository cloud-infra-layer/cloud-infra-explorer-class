require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
abort "RSpec must run with RAILS_ENV=test." unless ENV["RAILS_ENV"] == "test"

require_relative "../config/environment"
require "rspec/rails"
require "capybara/rails"
require "capybara/rspec"
# Share the PostgreSQL compatibility fix without loading Minitest's runner.
require_relative "../test/support/postgresql_referential_integrity"

ActiveRecord::Migration.maintain_test_schema!

# These server-rendered journeys need no JavaScript or external browser.
Capybara.default_driver = :rack_test

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  # Examples create explicit records. Do not load seeds or global fixtures.
end
