# Cloud Infrastructure Explorer

Cloud Infrastructure Explorer is a web application designed to make AWS infrastructure easier to discover, understand, and navigate.

The project is being developed by a four-person team for Columbia University's COMS W4152: Engineering Software-as-a-Service.

## Project Overview

Our initial MVP focuses on:

- Discovering EC2 instances and S3 buckets in AWS.
- Displaying resources through a simplified dashboard.
- Viewing resource details and associated metadata.
- Searching, pinning, and hiding resources.
- Performing manual, read-only infrastructure scans.

**Team sandbox region:** `us-east-2` (US East, Ohio), where the team's AWS test sandbox is set up. The adapter scans the region supplied in `connection_context`; it is not restricted to the sandbox region.

The application uses a Ruby on Rails monolith with PostgreSQL. The AWS adapter supports read-only EC2 and S3 discovery. Environment and resource models, fictional demo seeds, and a dashboard of stored resources are implemented; wiring live scans into persistence remains pending.

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

Before submitting changes, run:

```bash
bin/rails test
```

For system tests:

```bash
bin/rails test:system
```

Run the complete Rails CI checks locally with:

```bash
bin/ci
```

GitHub Actions also runs automated checks on the repository.

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
  views/           HTML templates
  javascript/      Frontend JavaScript
  jobs/            Background job definitions

config/            Application configuration
db/                Database schema and migrations
test/              Automated tests
.github/workflows/ GitHub Actions CI
Gemfile            Ruby dependencies
```

Additional services and directories will be introduced as features are implemented.

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

The dashboard currently reads stored records only. Running the adapter or `script/verify_resources.rb` returns discovery results without saving them to the database.

## Development Status

The initial Rails application, PostgreSQL configuration, repository, and continuous integration workflow are established.

The EC2/S3 adapter, mocked discovery tests, manual verification script, environment and resource models, demo seeds, and stored-resource dashboard are implemented. The initial scan coordinator is implemented; scan lifecycle management and persistence of live scan results remain Sprint 2 integration work. S3 discovery requires the additional read-only policy described in `docs/aws-setup.md`.

## Team

Developed by a four-person Columbia University software engineering team.

Repository: https://github.com/cloud-infra-layer/cloud-infra-explorer-class


