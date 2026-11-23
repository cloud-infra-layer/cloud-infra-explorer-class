# Cloud Infrastructure Explorer

Cloud Infrastructure Explorer is a shared AWS inventory dashboard that helps teams find important EC2 instances and S3 buckets, prioritize frequently used resources, and hide distracting inventory without modifying AWS infrastructure.

The project is being developed by a four-person team for Columbia University's COMS W4152: Engineering Software-as-a-Service.

## Deployment & Evaluation

- **Live SaaS Deployment (Heroku):** https://cloud-infra-explorer-class-8dbdbc772bf8.herokuapp.com/
- **GitHub Repository:** https://github.com/cloud-infra-layer/cloud-infra-explorer-class

> **Note for Teaching Staff / Graders:**
> Evaluating and testing this product does **NOT** require an AWS account or AWS credentials. 
> The application includes pre-seeded demo resources in PostgreSQL (`Course demo` environment), and all automated test suites (RSpec, Cucumber) use synthetic test databases and mocked AWS SDK responses.

Start with the EC2 or S3 category and search by resource name, service, or AWS ID.
The public UI currently supports browsing and search. Pin/hide persistence and
protected actions are implemented in the backend; the buttons and hidden-resource
navigation are pending frontend integration. Live refresh requires authorized
application access and configured read-only AWS credentials; it is not required
to evaluate demo inventory. A stored demo environment is not proof of a connected
AWS account or a successful live scan.

## Project Overview

Our MVP focuses on a **shared, curated view of the assets a team uses most**.
The intended workflow is to find a resource, pin it for quick access, hide
irrelevant inventory, and restore it when needed. These preferences belong to the
shared team view, not individual user accounts, and do not change resources in AWS.

This is a focused inventory interface rather than a replacement for AWS resource
administration.

### Implemented capabilities and remaining integration

| Capability | Current status |
|---|---|
| Browse stored EC2/S3 inventory and metadata | Available through category listings and dashboard counts |
| Search by name, service, or AWS resource ID | Implemented with category filtering and a basic search form |
| Shared pin/unpin and hide/restore | Database state and protected PATCH endpoints implemented; user-facing controls pending |
| Focus on important inventory | Backend orders pinned resources first and excludes hidden resources from normal listings/counts; pin indicators and prominent access to pinned assets remain frontend work |
| Find hidden resources | Backend supports `visibility=hidden`; navigation, restoration controls, and preservation of visibility in forms remain frontend work |
| Read-only EC2/S3 discovery | Adapter implemented; live access depends on deployment credentials and permissions |
| Persist scan results and scan history | ScanCoordinator and ResourceSync implemented, including partial/failure handling |
| Authorized manual refresh | Guarded endpoint and dashboard form implemented; available when scan configuration is enabled |

**Team sandbox region:** `us-east-2` (US East, Ohio), where the team's AWS test sandbox is set up. The adapter scans the region supplied in `connection_context`; it is not restricted to the sandbox region.

The application uses a Ruby on Rails monolith with PostgreSQL. An authorized
manual refresh follows this implemented flow:

`ScansController → ScanCoordinator → CloudProvider::Adapter → ResourceSync → PostgreSQL`

ScanCoordinator creates a running Scan, requests discovery, passes successful
service results to ResourceSync, and persists the final status, counts, timestamps,
and safe errors. ResourceSync updates existing resources in place, preserving
database IDs and personalization. Failed services and resources absent from a scan
do not cause stored inventory to be deleted. Views read PostgreSQL rather than
calling AWS directly.

See [AWS development setup](docs/aws-setup.md) for authentication, the discovery role, and the manual verification command.

## Technology Stack

| Technology | Purpose |
|---|---|
| Ruby 3.3.12 | Programming language |
| Rails 8.1.4 | Web application framework |
| PostgreSQL 15+ | Relational database |
| HTML / CSS / JavaScript | Frontend |
| Git / GitHub | Version control and collaboration |
| GitHub Actions | Continuous integration |
| AWS SDK for Ruby | Read-only EC2 and S3 resource discovery |

## Local Development Setup

These instructions use Ubuntu Linux, including Ubuntu through Windows Subsystem for Linux (WSL2).

macOS developers can use the same Ruby and Rails commands after installing the equivalent dependencies.

### 1. Install prerequisites

Required software:

- Git
- Ruby 3.3.12
- PostgreSQL 15+
- Bundler
- Required system libraries for Rails

**Windows developers:** Install WSL2 and Ubuntu first:

```powershell
wsl --install -d Ubuntu
```

Restart your computer if prompted, then open Ubuntu.

Inside Ubuntu, install system dependencies:

```bash
sudo apt update

sudo apt install -y \
  git curl build-essential autoconf bison \
  libssl-dev libyaml-dev libreadline-dev zlib1g-dev \
  libffi-dev libgmp-dev libpq-dev \
  libvips pkg-config
```

Install Ruby using [rbenv](https://github.com/rbenv/rbenv) and its [ruby-build](https://github.com/rbenv/ruby-build) plugin.

Once rbenv is configured, install the project Ruby version:

```bash
rbenv install 3.3.12
rbenv global 3.3.12
```

Confirm Ruby is installed:

```bash
ruby --version
```

Expected version: `3.3.12`.

Install Bundler if it is not already available:

```bash
gem install bundler
```

### 2. Clone the repository

First, accept your GitHub repository invitation.

Clone the project:

```bash
mkdir -p ~/GitHub
cd ~/GitHub

git clone https://github.com/cloud-infra-layer/cloud-infra-explorer-class.git
cd cloud-infra-explorer-class
```

Because this is a private repository, you must authenticate using an authorized GitHub account.

For Windows developers using WSL2, keep the project inside the Ubuntu filesystem rather than `/mnt/c/` for better development performance.

### 3. Install Ruby dependencies

From the project directory, run:

```bash
bundle install
```

This installs the gems specified in `Gemfile` and `Gemfile.lock`.

### 4. Configure PostgreSQL

Install PostgreSQL if necessary:

```bash
sudo apt install -y postgresql postgresql-contrib
```

Start the database service:

```bash
sudo service postgresql start
```

Create a PostgreSQL role for your local Linux user if one does not already exist:

```bash
sudo -u postgres createuser --createdb "$USER"
```

This configures a local development role capable of creating the application databases.

The application's default development configuration uses local PostgreSQL. Production database credentials should be provided through environment variables.

To note: The codebase utilizes ```nulls_not_distinct: true``` and ```NULLS NOT DISTINCT```, and they were only introduced starting from postgresql 15.

### 5. Initialize the database

Run:

```bash
bin/rails db:prepare
```

This creates or prepares the local database and loads the database schema.

### 6. Start the application

Run:

```bash
bin/rails server
```

Open:

http://localhost:3000

You should see the Rails application running.

Stop the server by pressing `Ctrl+C`.

### 7. Run tests

RSpec is the primary testing focus for course evaluation and new regression
coverage. Existing Minitest tests remain supplementary regression coverage;
Cucumber describes acceptance scenarios. All suites run without live AWS credentials.

The suites are not yet equivalent: adapter discovery, ScanCoordinator orchestration,
and the manual scan endpoint currently have Minitest coverage without corresponding
RSpec suites. Porting those behaviors to RSpec remains testing work; the presence
of RSpec alone does not imply every feature is covered by it.

Prepare the test database, then run suites sequentially:

```bash
RAILS_ENV=test bin/rails db:prepare
```

**1. RSpec — primary suite**:

```bash
bundle exec rspec
```

See [RSpec setup and coverage](spec/README.md) for local commands and test mapping.

**2. Minitest — supplementary regression suite**:

```bash
bin/rails test
```

**3. Cucumber User Stories (Acceptance & Feature BDD)**:

```bash
bundle exec cucumber
```
*(6 acceptance scenarios covering dashboard viewing, service categorization, and empty-state handling across `features/dashboard.feature` and `features/resource_browsing.feature`)*

**4. Rails system-test runner**:

The runner is configured in CI, but `test/system/` currently contains no system
test cases. Existing RSpec feature specs use Capybara RackTest; they do not verify
JavaScript or visual layout.

```bash
bin/rails test:system
```

**5. Full CI Checks (Linting & Security Analysis)**:

Run the complete local CI suite (RuboCop, Brakeman, bundler-audit, and tests):

```bash
bin/ci
```

GitHub Actions runs Rails tests, RSpec, Cucumber, lint, and security checks on pull
requests and pushes to `main`. `bin/ci` also runs all three test suites. See
[RSpec setup and coverage](spec/README.md) for the current coverage boundaries.

## Git Workflow

All development should happen on feature branches rather than directly on `main`.

### 1. Update your local repository

```bash
git switch main
git pull origin main
```

### 2. Create a feature branch

```bash
git switch -c feature/your-feature-name
```

Examples:

- `feature/aws-ec2-discovery`
- `feature/resource-dashboard`
- `feature/database-models`
- `feature/resource-search`

### 3. Make changes and test them

Implement your feature locally.

Run the relevant tests before submitting your work.

### 4. Commit your changes

```bash
git add .
git commit -m "Add resource dashboard"
```

Use descriptive commit messages.

### 5. Push your branch

```bash
git push -u origin feature/your-feature-name
```

### 6. Open a pull request

On GitHub:

1. Open the repository's **Pull Requests** tab.
2. Select **New pull request**.
3. Choose your feature branch and target `main`.
4. Describe your changes and how you tested them.
5. Request a review from another team member.

**Team convention:** Avoid merging your own PR without review. Merge only after required checks pass and review feedback is resolved.

After merging, teammates should pull the latest `main` before starting new work.

## Project Structure

```text
app/
  controllers/     Request handling
  models/          Application data models
  services/        AWS discovery, scan coordination, and inventory synchronization
  views/           HTML templates
  javascript/      Frontend JavaScript
  jobs/            Background job definitions

config/            Application configuration
db/                Database schema and migrations
spec/              Primary RSpec model, request, service, and feature coverage
test/              Supplementary Minitest regression coverage
features/          Cucumber acceptance scenarios
.github/workflows/ GitHub Actions CI
Gemfile            Ruby dependencies
```

Cross-component interfaces and frontend handoff details are documented in
[integration contracts](docs/integration-contracts.md).

## Security Guidelines

**Never commit credentials or secrets to GitHub.**

Do not commit:

- AWS access keys or secret access keys.
- Rails `config/master.key`.
- `.env` files containing credentials.
- Database passwords.
- API tokens or other private keys.

Use environment variables or approved secret-management mechanisms.

AWS access must initially be read-only and limited to the resources needed for the MVP.

Before committing changes, inspect the staged files:

```bash
git diff --cached --name-only
```

If credentials are accidentally committed, notify the team immediately and rotate the affected credentials.

## Troubleshooting

**PostgreSQL connection failure**

Make sure PostgreSQL is running:

```bash
sudo service postgresql start
pg_isready
```

**Database does not exist**

Run:

```bash
bin/rails db:prepare
```

**Missing Ruby gems**

Run:

```bash
bundle install
```

**Rails server does not start**

Check that you're in the project directory and using the correct Ruby version:

```bash
ruby --version
bundle exec rails --version
```

**Port 3000 already in use**

Stop the other Rails server, or run:

```bash
bin/rails server -p 3001
```

Then open http://localhost:3001.

## Demo inventory and dashboard

After preparing the development database, load fictional resources with:

```bash
bin/rails db:seed
```

Open `/` or `/dashboard` on the running Rails server to view stored EC2 and S3 resources across all environments. Loading seeds and viewing the dashboard do not call AWS or require AWS credentials.

The `Course demo` environment uses fictional `us-east-1` resources. It is separate from the team's live `us-east-2` sandbox and demonstrates that stored inventory is not restricted to the sandbox region. Rerunning seeds refreshes the demo records while preserving their database IDs and unrelated inventory. Keep the demo environment's name, provider, and region stable; changing them can create another demo environment. Manual edits to seeded resource attributes are overwritten on the next seed run.

The dashboard reads stored records. Running the adapter or
`script/verify_resources.rb` alone returns discovery results without saving them;
the implemented ScanCoordinator workflow persists both inventory and scan history.
Refreshing requires `ENABLE_MANUAL_SCANS=true`, `SCAN_ADMIN_USERNAME`,
`SCAN_ADMIN_PASSWORD`, and an appropriately configured AWS credential source.

Shared personalization writes are independently guarded by
`ENABLE_RESOURCE_PERSONALIZATION=true`, `RESOURCE_ADMIN_USERNAME`, and
`RESOURCE_ADMIN_PASSWORD`. Missing configuration disables the endpoints; enabled
writes require HTTP Basic authentication and Rails CSRF protection. Configure
credentials as runtime secrets and use HTTPS in deployment. No AWS credentials are
needed to personalize stored demo inventory. Hidden state is a presentation
preference, not an access-control boundary.

## Development Status

The initial Rails application, PostgreSQL configuration, repository, and continuous integration workflow are established.

Implemented: read-only EC2/S3 discovery, scan orchestration and persistence,
protected manual refresh, stored inventory browsing/search, and shared
personalization persistence and endpoints. S3 discovery requires the read-only
policy described in [AWS development setup](docs/aws-setup.md).

Remaining work: complete the frontend curation workflow described above, extend
acceptance scenarios to demonstrate that workflow, and add RSpec counterparts
for discovery and scan orchestration/endpoint coverage. The feature table above
distinguishes implemented backend functionality from the experience available to
an evaluator; deployment of code does not by itself verify live AWS connectivity.

## Team

Developed by a four-person Columbia University team for **COMS W4152: Engineering Software-as-a-Service** (Fall 2026):

| Member Name | Columbia UNI | Project Responsibility / Role | GitHub Handle |
|---|---|---|---|
| **Geonsik Moon** | `gm3239` | Cloud Integration & AWS Discovery | [@gsmoon97](https://github.com/gsmoon97) |
| **Ian Choi** | `ic2561` | Frontend & Product Development | [@IanJChoi](https://github.com/IanJChoi) |
| **Samuel Lee** | `sl5806` | Application & Data Architecture | [@slee4456](https://github.com/slee4456) |
| **Brayden Adcox** | `ba2851` | Technical Lead & Integration Engineering | [@braydenadcox](https://github.com/braydenadcox) |

Repository: https://github.com/cloud-infra-layer/cloud-infra-explorer-class


