# AWS development setup

Sprint 1 covers issues #5 (connectivity) and #7 (adapter), tracked by #6.
The team's sandbox uses **us-east-2 (Ohio)**. No S3 permissions or infrastructure
write permissions are needed by the adapter.

## Local prerequisites

Install the project's Ruby version and dependencies (`bundle install`). Install
AWS CLI v2 if needed:

```bash
brew install awscli
aws --version
```

Browser login requires AWS CLI 2.32.0 or newer. A project owner must invite each
developer individually. AWS Projects invitations grant broad project access;
use the restricted role below for discovery. Do not share login credentials or
commit AWS tokens, access keys, or files under `~/.aws`.

## Browser login

```bash
aws login --profile cloud-explorer-setup --region us-east-2
aws configure set region us-east-2 --profile cloud-explorer-setup
aws sts get-caller-identity --profile cloud-explorer-setup
```

Choose the team's sandbox project in the browser. The expected sandbox account
is `821058455060`; the setup session uses `AccountFullAccessRole`. Check that the
account matches before administering any resources. The project have been renamed
from its initial name, `Ready Set Build`.

## Read-only role (one-time account setup)

`CloudExplorerDiscovery` already exists in the team's sandbox. These commands
document how it was provisioned; developers should skip creation when joining.
Review the policy files before applying them to another account, particularly
the account-specific principal in the trust policy.

```bash
aws iam create-role \
  --role-name CloudExplorerDiscovery \
  --assume-role-policy-document file://config/aws/discovery-trust-policy.json \
  --max-session-duration 3600 \
  --profile cloud-explorer-setup --region us-east-2

aws iam put-role-policy \
  --role-name CloudExplorerDiscovery \
  --policy-name EC2DiscoveryOhio \
  --policy-document file://config/aws/ec2-discovery-policy.json \
  --profile cloud-explorer-setup --region us-east-2
```

The trust policy allows the sandbox's `managed/AccountFullAccessRole` to assume
this role. Its only resource permission is `ec2:DescribeInstances` in Ohio.
`Resource: "*"` is necessary because this API does not support individual
instance ARN restrictions. No changes to the AWS-managed setup role are needed.

## Configure each developer's local profiles

Run these once after browser login. They write configuration, not static access
keys, to `~/.aws/config`:

```bash
aws configure set credential_process \
  'aws configure export-credentials --profile cloud-explorer-setup --format process' \
  --profile cloud-explorer-source
aws configure set region us-east-2 --profile cloud-explorer-source

aws configure set role_arn \
  arn:aws:iam::821058455060:role/CloudExplorerDiscovery \
  --profile cloud-explorer-dev
aws configure set source_profile cloud-explorer-source --profile cloud-explorer-dev
aws configure set region us-east-2 --profile cloud-explorer-dev
aws configure set duration_seconds 3600 --profile cloud-explorer-dev
```

The intermediary `credential_process` profile is needed because the pinned Ruby
SDK supports browser login directly but does not resolve `login_session` as an
assume-role source profile. The CLI supplies temporary source credentials to the
SDK without storing permanent keys. Do not run the export-credentials command
by itself or paste its output into logs or issues.

The profile chain is: browser login → credential process → discovery role.
Only use `cloud-explorer-dev` for the adapter. This limits ordinary application
requests; it is not isolation from untrusted code on a laptop that also holds
the administrator session. A deployed application needs its own workload identity.

Verify the restricted identity:

```bash
aws sts get-caller-identity --profile cloud-explorer-dev
```

The ARN should contain `assumed-role/CloudExplorerDiscovery/`.

## Verify real EC2 discovery

From the repository root:

```bash
AWS_PROFILE=cloud-explorer-dev bundle exec ruby script/verify_ec2.rb
```

This calls the adapter without starting Rails or requiring PostgreSQL. It prints
the normalized resource/error contract and exits with status 1 if discovery fails.
Resources include IDs, names, instance types, states, region, and console URLs.
Avoid putting secrets in resource names. Review output before sharing it.

An empty `resources` array with an empty `errors` array is a successful scan of
an empty account. To demonstrate actual metadata, a team administrator can use
the optional test-instance helper below. The verification script itself never
creates, starts, stops, or deletes infrastructure.

For Rails console integration:

```bash
AWS_PROFILE=cloud-explorer-dev bin/rails console
```

```ruby
CloudProvider::Adapter.new.list_resources(
  provider: "aws", region: "us-east-2", resource_types: ["ec2"]
)
```

The SDK uses its standard credential provider chain. Remove stale
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` environment
variables if they override the intended profile. Credentials are never supplied
in `connection_context`.

## Optional disposable EC2 test instance

Use `script/ec2_test_instance.sh` for a manual live check. It calls AWS CLI using
**cloud-explorer-setup**, not the read-only discovery profile. Keep creation and
cleanup out of CI. These operations consume credits or incur charges for compute
and EBS; the script does not promise free usage.

The helper is fixed to account `821058455060` and region `us-east-2`, and checks
the caller's account before accessing EC2. It creates one Amazon Linux 2023
`t3.micro`, an encrypted 8 GiB gp3 root volume, and a dedicated security group.
There is no public IP, inbound or outbound security-group access, SSH key, user
data, or instance IAM role. IMDSv2 is required and CPU credits use standard mode.
Discovery only calls AWS APIs; it doesn't need network access into the instance.

First, log in and list existing subnets:

```bash
aws login --profile cloud-explorer-setup --region us-east-2
aws ec2 describe-subnets \
  --profile cloud-explorer-setup --region us-east-2 \
  --query 'Subnets[].{Subnet:SubnetId,VPC:VpcId,AZ:AvailabilityZone,State:State}' \
  --output table
```

Choose an available sandbox subnet. The helper does not create a VPC, subnet,
gateway, or other shared networking. If there is no subnet, coordinate with the
team before creating networking. The setup identity also needs SSM GetParameter
for the public Amazon Linux AMI parameter and EC2 permissions to describe images
and subnets, create/tag an instance and security group, remove egress rules,
terminate the instance, and delete the group. Do not add these permissions to
`CloudExplorerDiscovery`.

Choose a unique run ID (for example, your username plus a timestamp). Use the
same ID for cleanup, and never reuse it for a new run or copy its tags onto
unrelated resources. Replace the example subnet ID with your chosen subnet:

```bash
TEST_RUN="gm3239-$(date -u +%Y%m%d%H%M%S)"
bash script/ec2_test_instance.sh create "$TEST_RUN" subnet-REPLACE_ME

AWS_PROFILE=cloud-explorer-dev bundle exec ruby script/verify_ec2.rb

bash script/ec2_test_instance.sh cleanup "$TEST_RUN"
```

The create command prints its instance ID and cleanup command before waiting
for the running state. Check that the adapter reports that ID, the name
`cloud-explorer-test-<run-id>`, `t3.micro`, `running`, and `us-east-2`. Save reviewed
verification evidence in the PR. If EC2's eventually consistent API hasn't
returned the instance yet, retry discovery shortly afterward.

**Run cleanup even if verification fails or the shell is interrupted.** This
helper does not schedule automatic cleanup. It finds resources by both
`ManagedBy=cloud-explorer-live-test` and `TestRun=<run-id>` tags, so no local state
file is required. It refuses multiple matching instances or security groups.
Cleanup terminates the matching instance, waits for termination, and deletes
the matching group (retrying temporary dependency errors). The launch config
sets the root volume and network interface to delete on termination. It never
deletes the existing VPC or subnet.

If creation fails after creating a group, run cleanup with the printed run ID.
If cleanup fails, rerun it and inspect the tagged resources in the console;
do not assume a failed command removed everything. Stopping the instance is not
a substitute for cleanup because its storage remains. Repeating cleanup when
no matching resources remain is safe. Repeating create while its tagged
instance is still visible returns that instance instead of launching another;
each new test must use a fresh run ID.

The helper is tested with a fake AWS CLI; these tests do not create resources:

```bash
bundle exec ruby test/scripts/ec2_test_instance_test.rb
```

The helper has also been exercised against a live instance. See the discovery
and cleanup results in the verification evidence below.

## Tests and troubleshooting

Credential-free unit tests (no network or database needed):

```bash
bundle exec ruby test/services/cloud_provider/adapter_test.rb
```

The same tests are included in `bin/rails test` and GitHub CI; do not add AWS
secrets to CI. Tests cover mapping, pagination, empty inventories, later-page
failures, authentication, authorization, networking, and unsupported services.

- **Expired session:** rerun `aws login --profile cloud-explorer-setup --region us-east-2`.
- **Credentials unavailable:** confirm all three profiles above exist and that
  `aws` is on PATH. Restart a long-running Rails process after refreshing login.
- **AWS API error:** check the role identity, its policy, and the region. The
  adapter intentionally avoids returning raw SDK exception messages.
- **Network error:** check connectivity and retry; existing inventory must be preserved.
- **Empty inventory:** confirm the test instance belongs to this account and region.

## Verification evidence

On October 27, 2026, the Ruby verification script successfully called EC2 through
`CloudExplorerDiscovery` in account `821058455060`, region `us-east-2`, returning
`{"resources":[],"errors":[]}`. This initial check verified discovery of an empty
inventory.

The developer subsequently reported a successful live test using run ID
`gm3239-20261028025258` (the run ID uses UTC). The following command returned one
normalized resource and no errors:

```bash
AWS_PROFILE=cloud-explorer-dev bundle exec ruby script/verify_ec2.rb
```

| Field | Observed value |
|---|---|
| Provider | `aws` |
| Resource ID | `i-0d4e52323d532b770` |
| Service | `ec2` |
| Name | `cloud-explorer-test-gm3239-20261028025258` |
| Region | `us-east-2` |
| Instance type | `t3.micro` |
| State | `running` |
| Console URL | `https://us-east-2.console.aws.amazon.com/ec2/home?region=us-east-2#InstanceDetails:instanceId=i-0d4e52323d532b770` |
| Errors | `[]` |

The developer then ran:

```bash
bash script/ec2_test_instance.sh cleanup gm3239-20261028025258
```

AWS accepted termination of `i-0d4e52323d532b770`, reporting a transition from
`running` to `shutting-down`. The helper subsequently reported cleanup completed;
its completion path waits for instance termination and removes the tagged test
security group. The root volume was configured with `DeleteOnTermination=true`;
the supplied output does not independently verify volume deletion. No test
instance needs to remain running for the mocked tests.

IAM policy simulation allowed `ec2:DescribeInstances` in Ohio and denied
`ec2:RunInstances` and `ec2:TerminateInstances`. A simulation of the deployed role
also denied discovery in `eu-west-1`. The Ruby SDK's STS identity check confirmed
that it uses `assumed-role/CloudExplorerDiscovery/`.

## References

- [AWS CLI browser login and credential-process compatibility](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [Ruby SDK authentication](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/credentials.html)
- [EC2 action and region restrictions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html)
- [Assume-role profiles](https://docs.aws.amazon.com/sdkref/latest/guide/feature-assume-role-credentials.html)
- [EC2 CLI launch options](https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html)
- [Amazon Linux 2023 AMI parameters](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html)
