# RSpec testing and coverage

RSpec is the primary testing focus for course evaluation and new regression
coverage. The existing `test/` Minitest suite remains supplementary regression
coverage and is not removed. Maintain both suites where they cover shared behavior.
Cucumber scenarios in `features/` provide additional acceptance coverage.

RSpec now includes counterparts for AWS adapter discovery, ScanCoordinator,
and manual scan requests, alongside inventory and personalization coverage.
This is behavior coverage, not a claim of complete line coverage or exact parity
with every Minitest case. Test execution and CI results must be verified separately.

## Setup and local execution

```bash
bundle install
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec spec/models/scan_spec.rb --format documentation
bundle exec rspec spec/services/resource_sync_spec.rb --format documentation
bundle exec rspec spec/services/resource_sync_concurrency_spec.rb --format documentation
bundle exec rspec spec/features spec/requests --format documentation
bundle exec rspec spec/services/cloud_provider/adapter_spec.rb --format documentation
bundle exec rspec spec/services/scan_coordinator_spec.rb spec/requests/scans_spec.rb --format documentation
bundle exec rspec
bin/rails test
bundle exec cucumber
bin/rubocop
```

RSpec configuration is already checked in; do not run `rspec:install` over it.
Keep `Gemfile.lock` committed when intentionally changing dependencies. The gem
is explicitly required by `rails_helper.rb`, so ordinary Rails boot does not
load RSpec or change the existing generator defaults.

Run all available specs with `bundle exec rspec`. Examples run in random order;
use the printed seed to reproduce an order-dependent failure:

```bash
bundle exec rspec --seed 12345
```

Rails-backed specs require the test environment and configured PostgreSQL test
database. The adapter spec requires only `spec_helper` and the adapter source;
running it alone does not boot Rails or connect to PostgreSQL. SDK clients use
`stub_responses: true`, and both factories are explicitly supplied.
Records are created explicitly in database examples, without development seeds,
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
| `spec/models/resource_search_spec.rb` | Resource search controller tests | Case-insensitive matching, blank queries, literal special characters, category composition, and environment isolation |
| `spec/models/resource_personalization_spec.rb` | Resource personalization model tests | Defaults, pin/hide persistence, restoration semantics, visibility scopes, ordering, and non-null constraints |
| `spec/features/resource_search_spec.rb` | Resource search controller tests | Search form submission, category selection, no-match feedback, and clearing search |
| `spec/requests/resource_personalization_spec.rb` | Resource personalization controller tests | Protected PATCH actions, authentication, disabled configuration, repeatability, field restrictions, restoration, and CSRF protection |
| `spec/requests/resource_visibility_spec.rb` | Resource visibility controller tests | Visible/hidden filtering, combined search/category filters, pinned ordering, and visible-only dashboard counts |
| `spec/services/cloud_provider/adapter_spec.rb` | EC2 and S3 adapter tests | Seven-field normalization, stable identities, metadata allowlists, regions, pagination, invalid input, credential/API/network errors, empty results, and partial-service survival |
| `spec/services/scan_coordinator_spec.rb` | ScanCoordinator tests | Persisted scan lifecycle, real resource synchronization, counts, repeatability, personalization, partial/failed discovery, safe errors, and input validation |
| `spec/requests/scans_spec.rb` | Scans controller tests | Access guards, credential failures, input validation, CSRF, HTTP-to-database integration, feedback, and dashboard refresh presentation |

The ResourceSync specs also exercise input immutability, clearing optional fields,
null-region duplicates, destroyed environments, and rollback after both model
validation errors and real PostgreSQL constraint violations. The database-failure
example adds a temporary constraint inside the example's transaction; rollback
removes it. A caller can still save a failed Scan after rescuing the sync error.
Personalization regressions also verify that refreshes preserve pins, hidden state,
and database IDs, while discovery batches cannot supply personalization fields.
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
they do not exercise the implemented manual scan endpoint or coordinator. Browsing examples
also reject attempts to instantiate the discovery adapter or coordinator.
Request specs exercise HTTP status codes and escaping separately from navigation.

`describe` groups a subject or behavior, `context` describes circumstances, and
`it` defines an individual example. `let` creates example-local data lazily.
Expectations use `expect(...).to` or `expect { ... }.to change(...)`.

Scan model examples verify storage and validation. Separate coordinator specs
verify status decisions and persistence using an injected verifying adapter double.
Scan request specs keep the actual coordinator and sync service, replacing only
discovery. This checks the HTTP-to-database path without network access.

## Rubric audit

The supplied testing requirement is: **"good test coverage in RSpec; well thought
out tests; tests pass."** No numeric coverage threshold or required spec types were
provided. The coverage table above maps concrete behaviors to executable specs.

| Rubric requirement | Evidence and verification |
|---|---|
| Good RSpec coverage | Model, service, request, and feature specs cover the inventory workflow, including the newly added discovery/orchestration boundaries |
| Well thought out tests | Success and failure paths, invalid input, real PostgreSQL constraints/rollback, concurrency, authentication/CSRF, and persistence across reloads are tested; partial scans must update successful services while preserving failed-service inventory and personalization |
| Tests pass | Run `bundle exec rspec` and check CI for the submitted commit; file presence or earlier passing results do not establish that new specs pass |

The adapter suite compares full normalized records and uses independently listed
credential-error cases. Coordinator tests use real persistence except for one
injected persistence-failure case; ResourceSync specs separately verify real
database rollback. Request tests use JSON when testing explicit empty arrays so
form encoding cannot turn invalid input into an absent parameter with defaults.

## Remaining coverage and CI

Existing Minitest tests remain unchanged as supplementary coverage. This audit
closes the three identified service/request gaps, not every possible coverage gap:
for example, standalone Environment validation and the verification CLI still have
Minitest coverage without dedicated RSpec files. No line/branch percentage has been
measured. Existing Cucumber scenarios cover basic browsing; the completed curation UI will need
acceptance coverage for pin/hide/restore journeys. Backend request tests do not
establish that those controls are available to users. Rails system-test jobs are
configured, but `test/system/` currently contains no test cases.

GitHub Actions runs RSpec, Minitest, and Cucumber on pull requests and pushes to
`main`. `bin/ci` also runs all three suites, alongside style/security checks and
seed verification. CI tests use synthetic data and stubbed AWS responses; live
sandbox verification is separate and uses authorized read-only credentials.
Check the current commit's CI results before claiming that its tests pass.
