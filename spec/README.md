# RSpec examples alongside Minitest

The existing `test/` suite remains authoritative regression coverage and is not
removed. `spec/` provides parallel behavior-oriented RSpec examples for learning
and comparison. Update both versions when an intentionally shared behavior changes.

## Setup and local execution

```bash
bundle install
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec spec/models/scan_spec.rb --format documentation
bundle exec rspec spec/services/resource_sync_spec.rb --format documentation
bundle exec rspec spec/services/resource_sync_concurrency_spec.rb --format documentation
bundle exec rspec spec/features spec/requests --format documentation
bin/rails test
bin/rubocop
```

RSpec configuration is already checked in; do not run `rspec:install` over it.
`bundle install` updates `Gemfile.lock`; include that update in the PR. The gem
is explicitly required by `rails_helper.rb`, so ordinary Rails boot does not
load RSpec or change the existing generator defaults.

Run all available specs with `bundle exec rspec`. Examples run in random order;
use the printed seed to reproduce an order-dependent failure:

```bash
bundle exec rspec --seed 12345
```

The specs require the test environment and use the configured PostgreSQL test
database. Records are created explicitly in examples, without development seeds,
global fixtures, or AWS credentials. Transactional examples roll back their
changes. Run Minitest and RSpec sequentially when sharing the same test database.

Transactions do not hide records already present before an example starts.
Feature and request examples delete existing resources inside their individual
transactions before creating their own inventory, so page counts and empty states
are independent of leftover fixtures or seeds. Rollback restores those preexisting
resources; no database reset is needed.

`rails_helper.rb` shares the existing PostgreSQL compatibility support file but
does not load Minitest's `test_helper.rb` or runner.

## Current coverage

| RSpec file | Existing reference | Behaviors |
|---|---|---|
| `spec/models/scan_spec.rb` | `test/models/scan_test.rb`, scan-history example in `test/models/environment_test.rb` | Running and finished records, empty success, defaults, associations, requested services, counts, structured errors, timing, deletion protection, and database constraints |
| `spec/services/resource_sync_spec.rb` | `test/services/resource_sync_test.rb` | Creates, changed-only updates, repeatability, EC2/S3 identity, environment isolation, empty batches, malformed input, duplicate batches, and rollback |
| `spec/services/resource_sync_concurrency_spec.rb` | Additional RSpec coverage | Overlapping EC2 and S3 syncs wait on the environment lock and create one resource per identity |
| `spec/features/inventory_browsing_spec.rb` | Dashboard and resources controller tests | Cross-environment inventory, category navigation, counts, empty states, fallback values, and successful/rejected synthetic syncs reflected on the page |
| `spec/requests/inventory_spec.rb` | Dashboard and resources controller tests | Dashboard routes, invalid service filters, unfiltered inventory, and HTML escaping of stored fields and metadata |

The ResourceSync specs also exercise input immutability, clearing optional fields,
null-region duplicates, destroyed environments, and rollback after both model
validation errors and real PostgreSQL constraint violations. The database-failure
example adds a temporary constraint inside the example's transaction; rollback
removes it. A caller can still save a failed Scan after rescuing the sync error.
This is persistence integration coverage, not a test of ScanCoordinator itself.

The concurrency spec disables transactional fixtures only for its own group.
It creates a committed environment and uses two worker connections plus an
observer connection (at least three pool connections are needed; the default is
five). The first sync runs inside a transaction held open while the observer
checks PostgreSQL's `pg_blocking_pids` to prove that the second sync waits for it.
After release, both calls must succeed with one creation and no duplicate row.
This covers EC2 and S3, including S3's null region, without mocking locks.
Bounded waits and statement timeouts prevent ordinary lock failures from hanging
the suite. An ensure block stops workers and deletes only that example's resources
and environment. A forcibly terminated process can leave these committed test
records behind. These specs verify same-environment identical batches, not every
possible concurrent update/failure ordering or throughput under load.

Feature specs use Capybara's RackTest driver to follow links and inspect rendered
HTML in process. They need no browser installation or JavaScript driver, and use
the same transactional test database. They do not verify CSS layout or JavaScript.
The sync examples call ResourceSync directly with synthetic normalized records;
they do not imply that a scan button or HTTP scan endpoint exists. Browsing examples
also reject attempts to instantiate the discovery adapter or coordinator.
Request specs exercise HTTP status codes and escaping separately from navigation.

`describe` groups a subject or behavior, `context` describes circumstances, and
`it` defines an individual example. `let` creates example-local data lazily.
Expectations use `expect(...).to` or `expect { ... }.to change(...)`.

Scan examples verify storage and validation. They do not claim to verify AWS
discovery or the coordinator's decisions about which final status to assign.

## CI status

GitHub Actions and `bin/ci` have not been changed to execute RSpec. Run it locally;
green existing CI checks are not evidence that these specs pass. Adding RSpec
to CI is a separate team decision.
